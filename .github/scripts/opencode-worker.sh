#!/bin/bash
# The hourly worker's queue logic: pick one issue, claim it, release it (#142).
#
# Usage:
#   opencode-worker.sh solo                    # -> prints "busy" if another run is working
#   opencode-worker.sh pick                    # -> prints "<owner/repo>\t<number>", or nothing
#   opencode-worker.sh claim <repo> <number>   # -> In Progress
#   opencode-worker.sh release <repo> <number> # -> back to Ready
#   opencode-worker.sh review <repo> <number>  # -> In Review, once a pull request exists
#   opencode-worker.sh check-command <path/to/AGENTS.md>   # -> the repository's own check
#   opencode-worker.sh check-prerequisite <path/to/AGENTS.md>  # -> what that check needs first, or nothing
#   opencode-worker.sh exports <file>          # -> the `export NAME=value` lines a prerequisite emitted, made safe
#   opencode-worker.sh failed-step             # -> the name of this run's failed step
#   opencode-worker.sh excerpt <file>          # -> its last lines, bounded and with every secret taken out
#   opencode-worker.sh previous-failures <repo> <number>  # -> how many times the worker has already failed here
#   opencode-worker.sh leak-check <file>...    # -> refuses if a secret this run holds is in what is about to be published
#
# **All of it is here rather than in the workflow**, for `board-self-check.sh`'s
# reason: a workflow's `run:` blocks cannot be tested, and the parts of this that
# can go wrong quietly — the ordering, the empty queue, a board write that failed
# — are exactly the parts a person will never notice from a green run.
# `.github/tests/opencode-worker.test.sh` proves them against a stubbed `gh`.
#
# ## The queue is the organisation, not this repository (`#231`, 2026-08-08)
#
# It used to be `gh issue list --repo "$GITHUB_REPOSITORY"`, so the worker could
# only ever see `kolonie-docs`. The queue there emptied on 2026-08-07 and nothing
# happened for a day, with labelled work sitting in other repositories that the
# worker had no way to look at.
#
# **The maintainer's decision, 2026-08-08: one worker for the whole organisation,
# hourly, one issue at a time.** So every subcommand below takes a repository as
# well as a number — an issue number alone identifies nothing across five
# repositories that each number from 1, which §4 says and which `board_item_for`
# already knew while `pick` did not.
#
# ### What the queue query costs, measured 2026-08-08
#
# `gh search issues` is served by GitHub's **search** allowance — 30 requests a
# minute — which is a third pool, separate from `core` and from `graphql`. A run
# of the query below moved neither of the two counters that the loop actually
# runs out of. The board read that joins status onto the result is the cost, and
# it is one read an hour: about **three points** against 5000.
#
# ### The credential now reaches five repositories instead of one
#
# Said here rather than left to be inferred, because a reader auditing this file
# should not have to work it out: `GITHUB_TOKEN` in the workflow is scoped to the
# repository hosting it, so the checkout and the push of a *target* repository
# use a credential with organisation reach. That is a widening and it is
# deliberate — see the workflow header for what bounds it.
#
# ## Two locks, and why the second one is what matters
#
# The workflow asks *am I already running* before calling this. That is the
# visible lock, and it is deliberately explicit rather than left to `concurrency`
# so that a person reading the log sees the decision.
#
# **The real lock is the claim.** `pick` only ever returns an issue in **Ready**,
# and `claim` moves it to **In Progress** — so an issue being worked no longer
# matches the query, and two runners that somehow overlapped still could not take
# the same one. The first lock is a courtesy; this one is structural.
#
# ## What this never does
#
# **It never removes the `agent:opencode` label.** Nothing in *this script* does,
# and that is still true: the label is queue membership and not a status, the
# board column says what is happening to an issue, and the label says who is
# allowed to work it.
#
# **The workflow removes it on a failure, and that is not a contradiction**
# (`#251`). A worker that dropped the label from an issue it had merely finished
# would be deciding the issue may never be tried again. Dropping it from one that
# just failed decides only that the *next* attempt is a person's to start —
# which is the smaller decision, and the one the alternative was making in
# reverse: `kolonie-infra#107` was taken three times in eighty minutes and
# refused identically, because retrying was the default and nobody had chosen it.
#
# **It never merges, never pushes to `main`, and never writes an issue comment
# with the board token.** Comments are `GITHUB_TOKEN`'s job, so the stored
# credential's only power stays moving a column.
set -uo pipefail

PROJECT_ID=${PROJECT_ID:-PVT_kwDOEmwuYs4BebbB}
STATUS_FIELD=${STATUS_FIELD:-PVTSSF_lADOEmwuYs4BebbBzhY1uQw}
STATUS_READY=${STATUS_READY:-ee5ea42c}
STATUS_IN_PROGRESS=${STATUS_IN_PROGRESS:-39185de7}
STATUS_IN_REVIEW=${STATUS_IN_REVIEW:-d66d01e2}

ORG=${ORG:-Kolonie-AI}
QUEUE_LABEL=${QUEUE_LABEL:-agent:opencode}

# The mark on an issue whose implementation the worker is **not permitted** to
# write, as opposed to one it merely failed at (`#250`).
#
# `opencode:failed` says *tried and not finished*, and its whole design is that a
# person can put `agent:opencode` back and get another attempt. That is the right
# default and it is wrong for exactly one case: an issue whose only possible
# implementation is a path the worker's own prompt forbids. `kolonie-infra#107`
# was taken three times in eighty minutes on 2026-08-09 and refused identically
# each time. **The worker was right every time** — the rule is load-bearing, and
# a worker that could edit `.github/workflows/` could change its own permissions,
# schedule and guard rails in a run nobody is watching. What was wrong was
# upstream: nothing in the queue could say *this cannot be done here*, so the
# only thing that could discover it was the worker, repeatedly.
#
# An issue carrying this is out of the queue whatever its labels say. It comes
# off when a person changes something about the issue, which is the point.
FORBIDDEN_LABEL=${FORBIDDEN_LABEL:-opencode:forbidden}

# The two paths the worker's prompt forbids it to touch. Named here so that a
# refusal quoting one is machine-distinguishable from a refusal about the issue,
# and so that AGENTS.md §5 and this file cannot drift apart silently — the test
# asserts both carry both.
FORBIDDEN_PATHS=${FORBIDDEN_PATHS:-.github/workflows/ opencode.json}
RUN_URL=${RUN_URL:-}

# How many labelled issues the search returns before the ordering runs. The
# ordering is done here rather than by the API (`#234`), so this is the size of
# the candidate set and not the size of the answer — one issue is always taken.
# 200 is far above any plausible queue; a queue that reached it would be a
# finding in itself.
SEARCH_LIMIT=${SEARCH_LIMIT:-200}

# `--limit 1000`, sized to be unreachable rather than sized to the board, for the
# reason AGENTS.md §6 gives: `gh project item-list` fetches the limit and filters
# *afterwards*, so a low one silently drops rows and exits zero.
BOARD_LIMIT=${BOARD_LIMIT:-1000}

die() {
  echo "$1" >&2
  exit "${2:-1}"
}

# The board item id for an issue, or nothing.
#
# **Repository and number, never a number alone.** The board spans five
# repositories whose issue numbers all start at 1, so `#204` is not an
# identifier — §4 says so, and this is where it is enforced in code.
board_item_for() {
  local repo=$1 number=$2
  gh project item-list 1 --owner "$ORG" --limit "$BOARD_LIMIT" --format json |
    jq -r --argjson n "$number" --arg repo "$repo" \
      '.items[] | select(.content.number == $n and .content.repository == $repo) | .id' |
    head -1
}

# The repository's own check command, read out of its `AGENTS.md`.
#
# ## Why it is read rather than mapped
#
# `#231` refuses a repository-to-command map in the workflow, for the reason
# this project keeps re-learning: a map is a second record of a fact each
# repository already states, and the second record goes stale without anybody
# editing it. `kolonie-platform` and `kolonie-website` run `npm run check`;
# nothing here should have to know that.
#
# ## The convention, and it is deliberately boring
#
# A heading whose text **ends with** `The check command`, and the first fenced
# block after it. That block's first non-blank line is the command.
#
# *Ends with*, rather than an exact match, because `kolonie-docs` numbers its
# sections (`## 11. The check command`) and the other four do not. A convention
# that only one repository's house style can satisfy is a convention that gets a
# per-repository exception, which is the map this was written to avoid.
#
# A visible heading rather than an HTML comment, on purpose: a marker nobody can
# see in the rendered file is a marker the next person editing that section
# deletes without noticing. This one is a section of the document, so removing it
# is a conscious act.
#
# ## No command means stop, not guess
#
# `#231`: *"If a repository's `AGENTS.md` does not name its check command, that
# is a defect in that file and the run should say so and stop."* A guessed
# `npm run check` in a repository with no `package.json` fails somewhere further
# in, with a message about npm rather than about the missing section.
#
# ## One reader, two headings (`#247`)
#
# The convention below is now used twice — *The check command* and *The check
# prerequisite* — so the parsing is a function of the heading rather than two
# copies of the same awk programme that drift apart. The heading arrives
# lowercased and is matched against a lowercased line, which is what lets
# `## 10. The check command` and `## The check command` both work.
first_fenced_block_under() {
  local file=$1 heading=$2
  awk -v heading="$heading" '
    tolower($0) ~ ("^#+ .*" heading "[[:space:]]*$") { section = 1; next }
    section && /^#+ / { exit }
    section && /^```/ { fence = !fence; if (!fence) exit; next }
    section && fence && NF { print; exit }
  ' "$file"
}

check_command_from() {
  local file=$1
  [ -f "$file" ] || die "no AGENTS.md at $file — cannot learn this repository's check command" 5

  local command
  command=$(first_fenced_block_under "$file" "the check command")

  if [ -z "$command" ]; then
    die "$file names no check command: it needs a 'The check command' heading with the command in a fenced block. Refusing to guess one." 5
  fi
  printf '%s\n' "$command"
}

# What the check needs in front of it, if the repository says it needs anything.
#
# ## Why this is read and not held here (`#247`)
#
# The worker re-runs the target's check after the model has finished, because an
# unattended agent reporting that it ran a check is the claim this workflow
# exists to stop taking on trust. **It was re-running it in an environment the
# check is designed to refuse.** `kolonie-platform`'s suite fails hard on an
# unset `DATABASE_URL` — deliberately, `operations/testing.md`: *"a suite that
# skips them silently reports green while covering nothing"* — and the worker
# provided no PostgreSQL. Run `31303638874`, 2026-08-09: the model found
# `npm run test:db:up` in the repository's own documentation, started the server,
# passed the whole check against it, and then the worker's re-run failed on the
# one thing the model had already solved. **The verification step was weaker than
# the thing it exists to verify.**
#
# The fix is the same shape as the check command one heading up, and for the same
# reason `#231` gives: a `services: postgres:16` block in the workflow would be
# repository-specific knowledge held in the worker, and the next repository with
# a prerequisite would discover this again. The repository that has the
# prerequisite is the repository that states it.
#
# ## Absent is an answer, and it is the common one
#
# `check-command` fails when a repository names none, because a check that cannot
# be run means the run cannot be verified. This is the opposite: four of the five
# repositories need nothing before their check, so **silence prints nothing and
# exits 0**. A missing section here is not a defect in that file.
check_prerequisite_from() {
  local file=$1
  [ -f "$file" ] || die "no AGENTS.md at $file — cannot learn this repository's check prerequisite" 5

  first_fenced_block_under "$file" "the check prerequisite"
}

# The environment a prerequisite handed back, and nothing else it printed.
#
# ## Why the output is filtered rather than sourced
#
# `npm run test:db:up` finishes by printing `export DATABASE_URL=…`, which is the
# repository's existing interface to a person: run this, then copy that line.
# Honouring it is what makes the prerequisite worth declaring — a command that
# starts a server the check then cannot find is not a prerequisite, it is a
# container.
#
# Sourcing the whole output would run every line the command chose to print, in
# this shell, with this run's credentials. So each line is matched against one
# shape — `export NAME=value` — and **re-emitted through `printf %q`**, which
# quotes the value for exactly one round of `eval`. A `$(…)`, a backtick or a
# `;` in the value therefore arrives as characters and not as a command.
#
# ## And a name a prerequisite may not set
#
# Setting `PATH` would redirect every command after it, and setting a token would
# hand the model's step a credential the workflow chose not to give it (`#246`).
# Neither is what "my check needs a database" means, so both are refused by name
# and said out loud rather than dropped.
EXPORTS_REFUSED=${EXPORTS_REFUSED:-PATH LD_PRELOAD LD_LIBRARY_PATH GH_TOKEN GITHUB_TOKEN BASH_ENV IFS}

exports_from() {
  local file=$1
  [ -f "$file" ] || die "no such file: $file" 1

  local line name value refused
  while IFS= read -r line; do
    [[ $line =~ ^export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
    name=${BASH_REMATCH[1]}
    value=${BASH_REMATCH[2]}

    # One layer of the quotes an emitter may have added. Anything left inside is
    # data, and `%q` below is what keeps it that way.
    if [ "${#value}" -ge 2 ]; then
      case $value in
        \"*\") value=${value:1:${#value}-2} ;;
        \'*\') value=${value:1:${#value}-2} ;;
      esac
    fi

    refused=no
    for banned in $EXPORTS_REFUSED; do
      if [ "$name" = "$banned" ]; then refused=yes; break; fi
    done
    if [ "$refused" = yes ]; then
      echo "refusing to let the check prerequisite set $name" >&2
      continue
    fi

    printf 'export %s=%q\n' "$name" "$value"
  done <"$file"
}

# ## Saying why a run failed, where the failure is announced (`#245`)
#
# A failed run used to say *it failed, here is a link* — on the issue, in the
# Actions list, and on the run page, which had no summary at all. To learn that
# run `31302611039` died because three of the worker's own scratch files tripped
# `prettier --check`, somebody had to expand *Work it* and read past several
# hundred lines of build output. The maintainer, 2026-08-09: *"man kann nicht so
# richtig sehen, woran es liegt."*
#
# The three pieces below are what the workflow needs to say it instead, and they
# are here rather than in a `run:` block because a `run:` block cannot be tested
# — which is the reason this whole file exists.

# The marker that makes a failure comment countable. It is the opening of the
# comment the workflow has written since `#142`, unchanged on purpose: changing
# it would make every failure before today invisible to the count below.
# **Deliberately shorter than the sentence it matches** (`#251`). The comment
# opened with *The hourly opencode worker failed…* until `50ae76a` dropped the
# word when the schedule stopped being hourly — and the marker did not follow, so
# for two commits every failure was invisible to this count. Matching from
# `opencode worker failed` leaves it true of both wordings, so the history stays
# countable and the cadence can change again without silently breaking it.
FAILURE_MARKER=${FAILURE_MARKER:-opencode worker failed on this issue}

# How much of a log may reach a public comment. Three separate bounds, because
# they fail differently: a single line of minified output can be a megabyte, a
# tail of twenty can still be long, and the comment must stay readable.
EXCERPT_LINES=${EXCERPT_LINES:-20}
EXCERPT_LINE_CHARS=${EXCERPT_LINE_CHARS:-300}
EXCERPT_CHARS=${EXCERPT_CHARS:-2000}

# The variables whose *values* must not leave this runner — redacted out of a
# comment by `excerpt` (`#245`) and refused outright by `leak-check` (`#246`).
#
# **One list, because it is one fact.** Same technique as `no-gateway-leak.sh`:
# the values arrive in the environment and this file never learns them at rest.
# A variable that is unset, or shorter than ten characters, is skipped — a short
# needle would match half of any text and turn the excerpt into `[redacted]` or
# refuse every pull request.
GUARDED_SECRETS=${GUARDED_SECRETS:-OPENCODE_LLM_API_KEY OPENCODE_LLM_BASE_URL OPENCODE_LLM_MODEL GH_TOKEN GITHUB_TOKEN WORKER_REPO_TOKEN BOARD_READ_TOKEN BOARD_WRITE_TOKEN}

# **GitHub masks a secret's value in a log. It does not mask it in a comment.**
# That is the whole reason this is more than a `tail`: the excerpt is being moved
# from a place the platform protects to a place it does not.
#
# Two passes, and both are needed. By value catches the secrets this run holds,
# exactly and whatever they look like. By shape catches what value-matching
# cannot: a credential the target repository printed, a token in somebody else's
# output, an environment dump. Neither is sufficient alone.

# One line of arbitrary output, made safe to put in a public comment.
#
# **Lifted out of `excerpt_from` for `#254`** and otherwise unchanged. That
# ending now has a second thing to publish — the model's account of why the
# check failed — and two redactions would be two things to keep in step. There
# is one, and everything that leaves this runner goes through it.
redact_line() {
  local line=$1 name value

  # By value first, with bash's literal replacement rather than a regex, so a
  # secret containing `/` or `.` cannot escape the substitution.
  for name in $GUARDED_SECRETS; do
    value=${!name:-}
    [ "${#value}" -ge 10 ] || continue
    line=${line//"$value"/[redacted: the value of $name]}
  done

  # Then by shape. The last rule is the one that catches a `postgres://` or an
  # `https://user:pass@` that nothing in this run put there.
  #
  # **The `NAME=value` rule runs before the token-shaped ones**, and the order
  # is not arbitrary: with it last, `GH_TOKEN=ghp_…` was redacted twice — once
  # into `[redacted: a GitHub token]` and then again over the front of that —
  # leaving `GH_TOKEN=[redacted] a GitHub token]`. Nothing leaked, and it read
  # like something had.
  line=$(sed -E \
      -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' \
      -e 's/([A-Za-z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|APIKEY|CREDENTIAL))=[^[:space:]]+/\1=[redacted]/g' \
      -e 's/gh[pousr]_[A-Za-z0-9]{16,}/[redacted: a GitHub token]/g' \
      -e 's/github_pat_[A-Za-z0-9_]{20,}/[redacted: a GitHub token]/g' \
      -e 's/(sk|xoxb|xoxp|xapp)-[A-Za-z0-9_-]{16,}/[redacted: an API key]/g' \
      -e 's/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+/[redacted: a token]/g' \
      -e 's/[Bb]earer[[:space:]]+[A-Za-z0-9._~+/-]{16,}=*/[redacted: a bearer token]/g' \
    -e 's#://[^/@:[:space:]]+:[^/@[:space:]]+@#://[redacted: credentials]@#g' \
    <<<"$line")

  # A fenced block is what carries this into a comment, so three backticks in
  # the output would end the fence and let the rest render as prose.
  line=${line//'```'/\'\'\'}
  line=${line//$'\r'/}

  if [ "${#line}" -gt "$EXCERPT_LINE_CHARS" ]; then
    line="${line:0:$EXCERPT_LINE_CHARS}… (line truncated)"
  fi
  printf '%s\n' "$line"
}

excerpt_from() {
  local file=$1
  [ -f "$file" ] || return 0

  local line out=""
  while IFS= read -r line; do
    out+="$(redact_line "$line")"$'\n'
  done < <(tail -n "$EXCERPT_LINES" "$file")

  # Trailing newline off, then the last bound. The comment says the run link
  # carries the rest, so a cut here loses nothing that cannot be gone and read.
  out=${out%$'\n'}
  if [ "${#out}" -gt "$EXCERPT_CHARS" ]; then
    out="${out:0:$EXCERPT_CHARS}"$'\n'"… (excerpt truncated at $EXCERPT_CHARS characters; the run log has the rest)"
  fi
  printf '%s\n' "$out"
}

# Which step went red. Read from the API rather than tracked in a file, because
# the steps that fail hardest — a checkout, an install — are the ones that cannot
# be made to write a file first.
#
# **A job's log is not available while that job is still running**, which is why
# this returns a *name* and the excerpt comes from a file the run wrote as it
# went. The steps API does answer mid-run: a completed step carries its
# conclusion while the job around it is still `in_progress`.
#
# It never fails the caller. A reporting step that dies while reporting leaves
# exactly the silence it was added to remove.
# What the model is given to read when a check went red (`#254`).
#
# ## Why the tail alone was not enough
#
# The comment on a red check carries the last twenty lines of the build log —
# **bounded by line count rather than by relevance**, and the line that matters
# is usually above the cut. `kolonie-platform#533`'s sibling failures read as
# *`npm run check` did not pass* followed by a hundred lines of vitest output.
#
# So this is the tail **plus** the lines that look like the failure itself,
# wherever in the log they are. Every line goes through `redact_line`, which is
# the same filter the excerpt uses — the model must not be shown a credential
# any more than a reader must, and a model that has read one can put it in the
# account it writes.
#
# ## Bounded three ways, because the input is somebody else's build output
#
# The matched lines are capped, the total is capped, and the whole thing is a
# tail rather than the log — which the prompt says out loud, so the model does
# not describe what it cannot see.
DIGEST_MATCH=${DIGEST_MATCH:-FAIL|Error|error|✗|×|✘|not ok|AssertionError|Expected|Received|panic|SyntaxError|Cannot find|Module not found|✖}
DIGEST_LINES=${DIGEST_LINES:-60}
DIGEST_CHARS=${DIGEST_CHARS:-6000}

failure_digest_from() {
  local file=$1
  [ -f "$file" ] || return 0

  local line out=""
  # The matched lines first: they are the answer where there is one, and the
  # tail is context for them rather than the other way round.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    out+="$(redact_line "$line")"$'\n'
  done < <(grep -aE "$DIGEST_MATCH" "$file" 2>/dev/null | head -n "$DIGEST_LINES")

  out+=$'\n'"--- the last $EXCERPT_LINES lines ---"$'\n'
  out+="$(excerpt_from "$file")"

  if [ "${#out}" -gt "$DIGEST_CHARS" ]; then
    out="${out:0:$DIGEST_CHARS}"$'\n'"… (truncated at $DIGEST_CHARS characters)"
  fi
  printf '%s\n' "$out"
}

# The model's own account, made safe to publish.
#
# It is written by a model that ran with the gateway key in its environment, so
# it goes through the same filter as everything else — and through a bound,
# because *"answer in three short paragraphs"* is an instruction and not a
# guarantee.
ACCOUNT_CHARS=${ACCOUNT_CHARS:-1500}

redact_from() {
  local file=$1
  [ -f "$file" ] || return 0

  local line out=""
  while IFS= read -r line; do
    out+="$(redact_line "$line")"$'\n'
  done < "$file"

  out=${out%$'\n'}
  if [ "${#out}" -gt "$ACCOUNT_CHARS" ]; then
    out="${out:0:$ACCOUNT_CHARS}… (the model's account was longer than $ACCOUNT_CHARS characters and is cut here)"
  fi
  printf '%s\n' "$out"
}

# Which forbidden path a refusal named, or nothing (`#250`).
#
# ## Why this reads the refusal and not the issue
#
# `#250` refuses a scanner that guesses from an issue's text whether it needs a
# workflow edit: *"a classifier with a false-negative cost measured in wasted
# runs and a false-positive cost measured in work never attempted"*. This is the
# other end of the run and a different question. The model has already read the
# issue, already decided, and already written down which rule stopped it — so
# there is nothing to guess. A refusal naming `.github/workflows/` will recur
# identically for as long as the rule holds; one naming the issue may not.
worker_rule_refusal() {
  local file=$1 path
  [ -f "$file" ] || return 0
  for path in $FORBIDDEN_PATHS; do
    if grep -qF -- "$path" "$file"; then
      printf '%s\n' "$path"
      return 0
    fi
  done
}

failed_step() {
  local repo=${GITHUB_REPOSITORY:-} run=${GITHUB_RUN_ID:-}
  [ -n "$repo" ] && [ -n "$run" ] || return 0
  gh api "repos/$repo/actions/runs/$run/jobs" --paginate \
    --jq '[.jobs[].steps[]? | select(.conclusion == "failure") | .name] | .[0] // empty' \
    2>/dev/null || true
}

# How many times this issue has already been failed by the worker, counted off
# its own comments.
#
# **It counts failures on the issue and not failures in a row**, and the
# difference is worth stating rather than hiding behind the word *consecutive*:
# nothing writes a comment when a run succeeds, so there is no marker to reset
# against. A count of three means three failures on this issue, which is the
# finding either way — an issue the worker cannot do will produce them one after
# another, and one it can will not produce them at all.
previous_failures() {
  local repo=$1 number=$2
  local count
  count=$(gh api "repos/$repo/issues/$number/comments" --paginate \
    --jq "[.[] | select(.body | contains(\"$FAILURE_MARKER\"))] | length" 2>/dev/null) || count=""
  # `--paginate` with `--jq` prints one number per page, so they are added up
  # rather than read as one.
  [ -n "$count" ] || { echo 0; return 0; }
  awk '{ total += $1 } END { print total + 0 }' <<<"$count"
}

# The sentence every pull request the worker opens carries in its body.
#
# **Durable evidence, and deliberately not the author** (`#256`, `#258`). The
# obvious identifier is *whoever the token authenticates as*, and it is the one
# that goes wrong silently: the credential is a setting, it has already changed
# once, and a rotated token would make every pull request opened before it
# invisible to both sweeps below. The branch name is the second candidate and it
# is not enough on its own — anybody can push `opencode/issue-12`. The body
# sentence is written by this workflow and by nothing else, and a run that
# reworded it would have to edit the line the sweep reads.
WORKER_PR_MARKER=${WORKER_PR_MARKER:-Opened by the opencode worker for}

# The sentence that says an issue has already had its completion reported.
#
# Same shape and same job as `FAILURE_MARKER`: it is the opening of the comment
# the workflow writes, and the sweep below refuses to write a second one where it
# already appears. **Idempotency lives in the marker and not in a list of what
# has been reported**, because a list is state that has to be stored, and the
# issue timeline is a record that already exists and cannot drift from itself.
COMPLETION_MARKER=${COMPLETION_MARKER:-Completed by the opencode worker in}

# How far back the completion sweep looks. A run every ten minutes only ever
# needs to cover the gap since the last one; a day is two orders of magnitude of
# slack against that and still bounds the work at *what the worker merged in a
# day*, which has been about fifteen.
#
# **What it gives up, stated rather than discovered:** a completion that goes
# unreported for a whole day — the worker disabled, the schedule dropped — is
# never reported. That is a missing comment and not a wrong one, and the
# alternative is a sweep whose cost grows for as long as the experiment runs.
REPORT_WINDOW_DAYS=${REPORT_WINDOW_DAYS:-1}

# Every pull request the worker has opened, in one state, newest first.
#
# **Over REST search rather than the board or GraphQL**, for AGENTS.md §6's
# reason: the board is the whole of the GraphQL bill and this runs on a schedule
# every ten minutes. `search/issues` costs nothing from that pool.
#
# **The index is a minute or two behind**, which is the one property worth
# stating: a pull request opened by *this* run cannot be found by *this* run.
# Both callers are sweeps over previous runs' work, so that latency is invisible
# to them — and it is the reason neither of them belongs at the end of the run
# that opened the pull request.
#
# The body comes back with each hit and is not decoration: it carries the issue
# number, which saves the caller one API call per pull request.
worker_pull_requests() {
  local state=$1 extra=${2:-}
  gh api search/issues -X GET \
    -f q="org:$ORG is:pr is:$state in:body \"$WORKER_PR_MARKER\" $extra" \
    -f sort=updated -f order=desc -f per_page=100 \
    --jq '.items[] | "\(.repository_url | sub(".*/repos/"; ""))\t\(.number)\t\(.body | gsub("\n"; " "))"' \
    2>/dev/null || true
}

# The issue a worker pull request was opened for, off its branch name.
#
# `Closes #N` in the body says the same thing and is what GitHub acts on; the
# branch is used here because it survives a body somebody has edited, and
# because the two disagreeing is a defect worth having the sweep notice rather
# than paper over. A ref that does not match the convention prints nothing and
# the caller skips it.
issue_of_branch() {
  local ref=$1
  [[ "$ref" =~ ^opencode/issue-([0-9]+)$ ]] || return 0
  echo "${BASH_REMATCH[1]}"
}

# The same number, read off the pull request body instead.
#
# It is here because the search result already carries the body, so the caller
# that only needs the issue number saves an API call per pull request — which is
# the difference between a sweep that scales with the experiment and one that
# does not. The branch is still the authority: the reporting step reads both and
# refuses to report when they disagree, because two records of one fact that
# have drifted is a defect worth stopping on rather than picking a winner for.
issue_of_body() {
  local body=$1
  [[ "$body" =~ $WORKER_PR_MARKER\ \#([0-9]+) ]] || return 0
  echo "${BASH_REMATCH[1]}"
}

# Open worker pull requests that git cannot merge, as `<repo> <pr> <issue>`.
#
# ## Why this is a sweep and not a step at the end of the run
#
# The run that opens a pull request ends minutes before anything can merge under
# it. `kolonie-platform#668` opened at 05:44 on 2026-08-10 and went `CONFLICTING`
# when `#670` merged later — nothing in `#668`'s own run could have observed
# that, so the observation has to happen in a *subsequent* run. `#257` closes
# most of the window before the pull request is opened; this is the net under
# what still gets through.
#
# ## `dirty`, and nothing else
#
# GitHub's `mergeable_state` has six values and only one of them is this issue.
# `blocked` is a required check that has not reported, `unstable` is a
# non-required one that failed, `behind` is a branch that is simply out of date
# and merges fine — treating any of those as a conflict would put a healthy
# pull request back in Ready.
#
# **`unknown` is not an answer and must not be read as one.** GitHub computes
# mergeability lazily: the first request after a change to `main` returns
# `unknown` and starts the computation. A sweep that read that as *not dirty*
# would be correct by luck, and one that read it as *dirty* would close pull
# requests that merge perfectly well. It is skipped, out loud, and the next run
# ten minutes later gets a real answer.
stale_pull_requests() {
  local repo number body state ref issue
  while IFS=$'\t' read -r repo number body; do
    [ -n "${repo:-}" ] && [ -n "${number:-}" ] || continue

    IFS=$'\t' read -r state ref < <(
      gh api "repos/$repo/pulls/$number" \
        --jq '"\(.mergeable_state)\t\(.head.ref)"' 2>/dev/null
    ) || continue

    case "${state:-}" in
      dirty) ;;
      unknown|"")
        echo "$repo#$number: GitHub has not computed mergeability yet; leaving it for the next run" >&2
        continue ;;
      *) continue ;;
    esac

    issue=$(issue_of_branch "${ref:-}")
    if [ -z "$issue" ]; then
      echo "$repo#$number conflicts but its branch (${ref:-none}) names no issue; leaving it for a person" >&2
      continue
    fi

    printf '%s\t%s\t%s\n' "$repo" "$number" "$issue"
  done < <(worker_pull_requests open)
}

# Merged worker pull requests whose issue does not yet say so, as
# `<repo> <pr> <issue>`.
#
# ## Why a successful issue needed this at all (`#258`)
#
# The worker announces when it takes an issue and explains every failure path. A
# **success** ended with neither: the pull request merged, GitHub closed the
# issue, and the only worker comment left behind was *"Taken by the opencode
# worker"*. Verified on `kolonie-platform#649`, `#657` and `#658` — each has a
# merged worker pull request and no closing account, so a reader has to open the
# pull request and reconstruct the result from its files.
#
# ## Why it is a sweep, and why it is the same sweep as `#256`'s
#
# The run that opens a pull request ends before GitHub merges it, so the run that
# did the work can never be the one that reports it landing. Both observations —
# *this one conflicted* and *this one merged* — are about previous runs and both
# belong at the start of the next one. **Opening a pull request is not
# completion**, which is the distinction this whole comment exists to make
# visible on the timeline.
#
# ## Exactly once, and nothing stored to make it so
#
# The marker is read off the issue's own comments. A reporting step that ran
# twice, a run that was retried, a sweep window that overlaps the last one — all
# find the marker and write nothing. There is no list of what has been reported,
# because a list is state that drifts from the thing it describes.
unreported_completions() {
  local since repo number body issue reported
  since=$(date -u -d "${REPORT_WINDOW_DAYS} days ago" +%Y-%m-%d 2>/dev/null) || since=""

  while IFS=$'\t' read -r repo number body; do
    [ -n "${repo:-}" ] && [ -n "${number:-}" ] || continue

    issue=$(issue_of_body "${body:-}")
    if [ -z "$issue" ]; then
      echo "$repo#$number is merged but its body names no issue; nothing to report on" >&2
      continue
    fi

    # The issue must be **closed**, and that is not the same question as *did
    # the pull request merge*. A merge whose `Closes #N` was edited out, or one
    # whose issue somebody reopened because the work was not enough, is not a
    # completion — and writing *completed* on an open issue would be the exact
    # misrepresentation this issue is about.
    if [ "$(gh api "repos/$repo/issues/$issue" --jq '.state' 2>/dev/null)" != "closed" ]; then
      continue
    fi

    reported=$(gh api "repos/$repo/issues/$issue/comments" --paginate \
      --jq "[.[] | select(.body | contains(\"$COMPLETION_MARKER\"))] | length" 2>/dev/null) ||
      continue
    [ -n "$reported" ] || continue
    [ "$(awk '{ total += $1 } END { print total + 0 }' <<<"$reported")" -eq 0 ] || continue

    printf '%s\t%s\t%s\n' "$repo" "$number" "$issue"
  done < <(worker_pull_requests merged "${since:+merged:>=$since}")
}

# Nothing that is about to be published carries a secret this run holds (`#246`).
#
# ## Why this exists next to a sandbox that was already there
#
# opencode's sandbox kept the model out of the runner's filesystem, on a
# container GitHub throws away. **It never kept it out of the credentials**,
# which were in its environment the whole time — a directory restriction does not
# stop `env`. So the cheap thing was guarded and the expensive one was not.
#
# The expensive one is this: the run writes a **public** pull request, and a
# model that has read a credential and is being thorough about documenting what
# it did can put it in a body, a commit message or a test fixture — not
# maliciously, just completely. GitHub masks a secret's value in a log. It does
# not mask it in a pull request.
#
# ## By value, and deliberately not by shape
#
# `excerpt` above redacts by shape as well, because there the cost of a false
# positive is a slightly less readable comment. Here the cost is a refused pull
# request and an hour of work returned to the queue, so the test is the one that
# cannot be wrong: does the literal value of a secret **this run holds** appear.
# A repository that legitimately documents what a token looks like is not a leak
# and must not be treated as one.
#
# **It prints no value, ever, including on failure** — the variable name and the
# file are enough to act on, and a grep hit echoed into a public log would be the
# leak this exists to prevent.
leak_check() {
  local failures=0 checked=0 name value file

  for name in $GUARDED_SECRETS; do
    value=${!name:-}
    [ -n "$value" ] || continue
    if [ "${#value}" -lt 10 ]; then
      echo "skip: $name is set but shorter than 10 characters, so it cannot be searched for safely" >&2
      continue
    fi
    checked=$((checked + 1))
    for file in "$@"; do
      [ -f "$file" ] || continue
      if grep -qF -- "$value" "$file"; then
        echo "REFUSED: the value of $name appears in $(basename "$file")" >&2
        failures=$((failures + 1))
      fi
    done
  done

  if [ "$failures" -gt 0 ]; then
    echo "Nothing was pushed. No value is printed above on purpose — the variable name and the file are enough to fix it." >&2
    return 1
  fi

  echo "$checked secret(s) checked against $# file(s); none of them appears in what is about to be published"
  return 0
}

set_status() {
  local item=$1 option=$2
  gh project item-edit --id "$item" --project-id "$PROJECT_ID" \
    --field-id "$STATUS_FIELD" --single-select-option-id "$option"
}

case "${1:-}" in
  pick)
    # Everything in the **organisation** carrying the label, with its repository,
    # labels and creation date. The board status is not on an issue, so it is
    # joined below rather than queried here.
    #
    # `gh search issues` rather than `gh issue list --repo`, which is the whole
    # of `#231`: the old form could only see the repository hosting the workflow,
    # and the queue there emptied on 2026-08-07 while labelled work sat in other
    # repositories. **One call for all five**, and it is served by GitHub's
    # search allowance — 30 a minute, a pool separate from `core` and `graphql`,
    # measured 2026-08-08 by reading `rate_limit` either side and seeing neither
    # of the two constrained counters move.
    #
    # `--limit` is the size of the *candidate set*, not of the answer: the
    # ordering (`#234`) happens locally, so all of it has to arrive before
    # anything can be sorted. Exactly one issue is ever returned.
    issues=$(gh search issues --owner "$ORG" --label "$QUEUE_LABEL" --state open \
      --limit "$SEARCH_LIMIT" --json repository,number,createdAt,labels) ||
      die "the queue could not be searched, so the queue is unknown"

    if [ -z "$issues" ] || [ "$(jq 'length' <<<"$issues")" -eq 0 ]; then
      echo "nothing queued: no open issue in $ORG carries $QUEUE_LABEL" >&2
      exit 0
    fi

    # ## Why the board goes through a file and not through `--argjson`
    #
    # It used to be `--argjson board "$board"`, and that put the whole board on
    # `jq`'s **command line**. The board is one JSON document of every item in
    # the project — 118 items and about 190 KB on 2026-08-07 — and `execve` has a
    # per-argument ceiling of 128 KiB on Linux whatever `ARG_MAX` says. So the
    # call died with `/usr/bin/jq: Argument list too long`.
    #
    # **It had never been reached.** The queue was empty on every one of the
    # forty-odd runs between this shipping on 2026-08-04 and the first labelled
    # issue on 2026-08-07, and the step before this one exits early on an empty
    # queue — so the line that could not run was the line nothing ran.
    #
    # `--slurpfile` reads the file itself, so nothing about the board's size
    # reaches the command line and the ceiling stops being a ceiling this script
    # can hit. It wraps the document in an array, hence `$board[0]`.
    board_file=$(mktemp)
    trap 'rm -f "$board_file"' EXIT
    gh project item-list 1 --owner "$ORG" --limit "$BOARD_LIMIT" --format json \
      >"$board_file" || die "could not read the board, so the queue is unknown"
    [ -s "$board_file" ] || die "the board came back empty, so the queue is unknown"

    # The ordering, and it is deterministic on purpose: two people reading the
    # queue must predict the same next issue. `p1` before `p2`, then oldest
    # first. An issue in any column but Ready is not in the queue, which is what
    # makes the claim a lock. `blocked:human` is excluded belt-and-braces — such
    # an issue should never carry the label, and if one does, the queue is the
    # wrong place to discover it.
    #
    # **The repository is matched as well as the number.** The board spans five
    # repositories and issue numbers repeat across them, so matching on the
    # number alone lets `kolonie-platform#204` decide whether `kolonie-docs#204`
    # is in Ready. Now that the search is organisation-wide this is no longer a
    # latent defect: the candidate set genuinely contains several repositories.
    # **`opencode:forbidden` is excluded here and not by the search**, so that
    # an issue carrying it is out of the queue even when somebody has put
    # `agent:opencode` back — which is exactly the case `#250` is about, and the
    # case a search term the labeller can overwrite would not cover.
    selection=$(jq -r --arg forbidden "$FORBIDDEN_LABEL" --slurpfile board "$board_file" '
      [ .[]
        | select([.labels[].name] | index("blocked:human") | not)
        | select([.labels[].name] | index($forbidden) | not)
        | { repo: .repository.nameWithOwner,
            number: .number,
            createdAt: .createdAt,
            labels: [.labels[].name] }
        | . as $issue
        | ($board[0].items[]
            | select(.content.number == $issue.number
                     and .content.repository == $issue.repo)) as $item
        | select($item.status == "Ready")
        | $issue + { rank: (if ($issue.labels | index("p1")) then 0
                            elif ($issue.labels | index("p2")) then 1
                            else 2 end) }
      ]
      | sort_by(.rank, .createdAt)
      | @json
    ' <<<"$issues") || die "the queue could not be read"

    # An issue carrying neither priority sorts **last** and the log names it
    # (`#234`). It is not skipped: refusing to run it would leave it queued
    # forever with nothing saying why. It is taken after everything that was
    # triaged, and the line below is what tells whoever labelled it that the
    # triage step was missed.
    jq -r '.[] | select(.rank == 2)
           | "note: \(.repo)#\(.number) carries neither p1 nor p2, so it sorts last"' \
      <<<"$selection" >&2

    jq -r '.[0] | select(. != null) | "\(.repo)\t\(.number)"' <<<"$selection"

    exit 0
    ;;

  claim)
    repo=${2:?claim needs a repository}
    number=${3:?claim needs an issue number}
    item=$(board_item_for "$repo" "$number")
    [ -n "$item" ] || die "$repo#$number is not on the board — refusing to start work on it" 3

    # **The board write happens before the comment and before any work.** An
    # expired or revoked token has to stop the run here, while nothing has been
    # started and nothing needs undoing. `#142` names this as the one failure the
    # design cannot recover from on its own: an issue parked in In Progress by a
    # token that then could not move it back.
    set_status "$item" "$STATUS_IN_PROGRESS" ||
      die "could not move $repo#$number to In Progress — the board token may have expired. Not starting work." 4

    exit 0
    ;;

  review)
    repo=${2:?review needs a repository}
    number=${3:?review needs an issue number}
    item=$(board_item_for "$repo" "$number")
    [ -n "$item" ] || die "$repo#$number vanished from the board" 3

    set_status "$item" "$STATUS_IN_REVIEW" ||
      die "could not move $repo#$number to In Review — a pull request exists and the board does not say so" 4

    exit 0
    ;;

  release)
    repo=${2:?release needs a repository}
    number=${3:?release needs an issue number}
    item=$(board_item_for "$repo" "$number")
    [ -n "$item" ] || die "$repo#$number is not on the board" 3

    # **Loudly, and on the issue**, because this is the recovery path and a
    # silent failure here is an issue parked in In Progress forever — which
    # `#142` says will be the issue that most needed attention.
    if ! set_status "$item" "$STATUS_READY"; then
      die "COULD NOT RELEASE $repo#$number back to Ready. It is stuck in In Progress and needs a person: $RUN_URL" 4
    fi

    exit 0
    ;;

  check-command)
    check_command_from "${2:?check-command needs a path to an AGENTS.md}"
    exit 0
    ;;

  check-prerequisite)
    check_prerequisite_from "${2:?check-prerequisite needs a path to an AGENTS.md}"
    exit 0
    ;;

  exports)
    exports_from "${2:?exports needs a file to read}"
    exit 0
    ;;

  failed-step)
    failed_step
    exit 0
    ;;

  excerpt)
    excerpt_from "${2:?excerpt needs a file to read}"
    exit 0
    ;;

  worker-rule-refusal)
    worker_rule_refusal "${2:?worker-rule-refusal needs a file to read}"
    exit 0
    ;;

  failure-digest)
    failure_digest_from "${2:?failure-digest needs a file to read}"
    exit 0
    ;;

  redact)
    redact_from "${2:?redact needs a file to read}"
    exit 0
    ;;

  previous-failures)
    previous_failures "${2:?previous-failures needs a repository}" \
      "${3:?previous-failures needs an issue number}"
    exit 0
    ;;

  stale-pull-requests)
    stale_pull_requests
    exit 0
    ;;

  unreported-completions)
    unreported_completions
    exit 0
    ;;

  leak-check)
    shift
    [ "$#" -gt 0 ] || die "leak-check needs at least one file to read" 1
    leak_check "$@"
    exit $?
    ;;

  solo)
    # *Am I the only run working right now?* Prints `busy` when a previous run is
    # still going, and nothing when it is not.
    #
    # **It moved here from the workflow's `run:` block for `#231`**, whose
    # acceptance criteria ask for a test covering the case where this query
    # fails — and a `run:` block cannot be tested, which is the reason the whole
    # of this file exists. Nothing about the behaviour changed in the move.
    #
    # ## A query that fails is not an answer, and does not stop the run
    #
    # The workflow header already argues this and the code now matches it: this
    # step is *the courtesy*, and the claim is the lock. `pick` only ever returns
    # an issue in Ready and `claim` moves it to In Progress, so two runs that did
    # overlap still could not take the same issue.
    #
    # So a `gh run list` that fails degrades into the structural lock rather than
    # into a stopped worker. **Loudly** — the alternative reading, that a failed
    # query means *stop*, turns a GitHub API blip into an hour of silence that
    # looks exactly like an empty queue, which is the confusion `#142` spent
    # three days on already.
    running=$(gh run list --repo "${GITHUB_REPOSITORY:?solo needs GITHUB_REPOSITORY}" \
      --workflow opencode-worker.yml --status in_progress \
      --limit 10 --json databaseId --jq 'length' 2>/dev/null)

    if [ -z "$running" ] || ! [ "$running" -eq "$running" ] 2>/dev/null; then
      echo "could not count in-progress runs; continuing, because the claim is the real lock" >&2
      exit 0
    fi

    echo "in_progress runs, counting this one: $running" >&2
    if [ "$running" -gt 1 ]; then
      echo "a previous run is still working. Exiting, and taking nothing." >&2
      echo busy
    fi
    exit 0
    ;;

  *)
    die "usage: opencode-worker.sh solo | pick | claim <repo> <n> | review <repo> <n> | release <repo> <n> | check-command <path> | check-prerequisite <path> | exports <file> | failed-step | excerpt <file> | failure-digest <file> | redact <file> | worker-rule-refusal <file> | previous-failures <repo> <n> | stale-pull-requests | unreported-completions | leak-check <file>..."
    ;;
esac
