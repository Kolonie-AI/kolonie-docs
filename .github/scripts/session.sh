#!/bin/bash
# One checkout, one session, and a commit that says which. `kolonie-docs#318`.
#
# Usage:
#   session.sh take [<agent>] [--branch <name>] [--force]   # claim this checkout
#   session.sh check                                        # what the hooks run
#   session.sh status                                       # who holds it, on what
#   session.sh release                                      # give it back
#   session.sh install-hooks                                # idempotent, `take` does it
#
# ## What went wrong, and why a habit was not the fix
#
# On 2026-08-12 two agent sessions worked in `~/github_repos/kolonie-docs` at the
# same time. The first left `fix/worker-board-read-with-the-board-app` checked
# out. The second arrived, ran `git pull --rebase && git push` four times over two
# hours, read the result each time, and pushed all four onto that branch believing
# it was `main`. Four issues were closed claiming a change `main` did not have.
#
# Every guard that existed was green. `git push` was green because the branch
# tracked a real remote branch; CI was green *on that branch*; `check.sh` was
# green *on that branch*. The one command that would have said so — `git status` —
# is not in the loop between `commit` and `push`, and asking an agent to run it is
# the guard that had already failed. `#318`:
#
# > **Not solved by "always check the branch".** That is the guard that failed
# > here, and it failed because it was a habit rather than a check.
#
# So this is a check. It runs from `pre-commit` and `pre-push`, where refusing is
# the only thing it can do.
#
# ## The three things that must agree
#
#   the environment    `KOLONIE_AGENT`   who is at the keyboard, this process
#   the claim file     `.git/kolonie-session`   who took this checkout, and on what branch
#   the working copy   `git symbolic-ref HEAD`  what would actually be committed to
#
# A commit is allowed when all three agree and refused, loudly, when any two
# disagree. Each disagreement is a different incident and each gets its own
# sentence — a single "refused" would send the reader to the wrong fix.
#
# **`KOLONIE_AGENT` unset is a refusal, not a pass.** That is deliberate and it is
# the case that catches `#318` itself: the second session never claimed anything,
# so a claim-versus-branch test alone would have found the branch matching the
# claim the *first* session left and waved it through. The environment is the only
# place the second session differs from the first, so it is the thing that has to
# be present.
#
# ## Why not a worktree per session
#
# `#318` lists `git worktree` first and it is the more correct answer: a branch
# becomes a property of the directory rather than of a shared `HEAD`, and two
# sessions then cannot be in the same working copy at all. It is not what this
# file does, for one reason — **it cannot be enforced from inside the repository.**
# An agent that `cd`s into the shared checkout is in the shared checkout, and
# nothing committed here changes that. A worktree is worth doing and this is worth
# having anyway, because this one refuses.
#
# ## The identity half
#
# `#318`'s second half: every commit on that machine carried one person's name, so
# `git log` could not say which session made which commit and the incident was
# reconstructable only from a local, unpushed, expiring reflog. `take` makes sure
# this checkout has an identity of its own. It prevents nothing — `#318` says so —
# and it is what makes the next one answerable. `kolonie-infra#137` is the same
# defect from the other end and the two are worth reading together.
#
# **It does not invent an address when one is already configured**, and that
# restraint is the whole of `kolonie-docs#230`: an agent's real identity is its
# GitHub account's `<id>+<handle>@users.noreply.github.com`, which is what links a
# commit to the account that made it. A generated address would be *distinct*,
# which is all `#318` asks for, and would quietly cost the attribution `#230` set
# up. So the order is:
#
#   1. a `user.email` already set **locally in this checkout** — left alone
#   2. `KOLONIE_AGENT_EMAIL` — used as given
#   3. `<agent>@noreply.kolonie.ai` — a distinct last resort, and it says so
#
# Only (3) is this file's invention, it is what `opencode-worker.yml` already
# commits as, and `take` prints a line pointing at `#230` whenever it lands there.
# What is refused in every case is the fall-through to `~/.gitconfig`, which is
# how six commits came to be authored by the maintainer.
#
# ## A claim goes stale, because an abandoned one is worse than none
#
# `AGENTS.md` §6 step 7 makes that argument about the board and it is the same
# argument here: a stop sign in front of work nobody is doing. A claim older than
# `KOLONIE_SESSION_TTL_HOURS` (default 8) has expired, and `take` walks over an
# expired one without asking. `--force` is for the other case — a live claim whose
# holder you know is gone — and it names who it displaced on the way past.

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT"

TTL_HOURS=${KOLONIE_SESSION_TTL_HOURS:-8}
CLAIM=$(git rev-parse --git-path kolonie-session 2>/dev/null) || {
  echo "session.sh: not a git repository: $ROOT" >&2
  exit 2
}

now() { date +%s; }

current_branch() {
  git symbolic-ref --quiet --short HEAD 2>/dev/null || echo "(detached HEAD)"
}

default_branch() {
  local ref
  ref=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) && {
    echo "${ref#origin/}"
    return
  }
  echo main
}

# Every reader of the claim gets the same four variables or none of them, so a
# half-written file reads as no claim rather than as a claim with empty fields.
read_claim() {
  CLAIM_AGENT= CLAIM_BRANCH= CLAIM_TAKEN= CLAIM_PID=
  [ -f "$CLAIM" ] || return 1
  local key value
  while IFS='=' read -r key value; do
    case "$key" in
      agent) CLAIM_AGENT=$value ;;
      branch) CLAIM_BRANCH=$value ;;
      taken) CLAIM_TAKEN=$value ;;
      pid) CLAIM_PID=$value ;;
    esac
  done < "$CLAIM"
  [ -n "$CLAIM_AGENT" ] && [ -n "$CLAIM_BRANCH" ] && [ -n "$CLAIM_TAKEN" ]
}

claim_age_hours() {
  echo $(( ( $(now) - CLAIM_TAKEN ) / 3600 ))
}

claim_is_stale() {
  [ $(( $(now) - CLAIM_TAKEN )) -ge $(( TTL_HOURS * 3600 )) ]
}

# `#318`: the branch was left behind by somebody, and who is the first thing you
# want when you are deciding whether to walk over it.
who_last_touched() {
  local branch=$1
  git log -1 --format='%an, %ar (%h %s)' "$branch" -- 2>/dev/null || echo "no commits"
}

hooks_dir() {
  local dir
  dir=$(git rev-parse --git-path hooks)
  mkdir -p "$dir"
  echo "$dir"
}

HOOK_MARK='# kolonie-docs#318 — installed by .github/scripts/session.sh'

install_hooks() {
  local dir hook path
  dir=$(hooks_dir)
  for hook in pre-commit pre-push; do
    path="$dir/$hook"
    if [ -e "$path" ] && ! grep -qF "$HOOK_MARK" "$path" 2>/dev/null; then
      echo "session.sh: $hook exists and is not ours — leaving it alone." >&2
      echo "            Add this line to it yourself, or move it aside:" >&2
      echo "              bash .github/scripts/session.sh check || exit 1" >&2
      continue
    fi
    cat > "$path" <<HOOK
#!/bin/bash
$HOOK_MARK
# Refuses a commit or a push when the environment, the claim and the branch do
# not agree. Regenerate with: bash .github/scripts/session.sh install-hooks
exec bash "\$(git rev-parse --show-toplevel)/.github/scripts/session.sh" check
HOOK
    chmod +x "$path"
  done
}

# Each refusal names the one disagreement it found and the one command that
# resolves it. A shared "refused" would be shorter and would send half its
# readers to the wrong fix.
refuse() {
  echo >&2
  echo "  ✗ $1" >&2
  shift
  local line
  for line in "$@"; do echo "    $line" >&2; done
  echo >&2
  exit 1
}

cmd_check() {
  local branch
  branch=$(current_branch)

  if ! read_claim; then
    refuse "This checkout is not claimed by any session." \
      "Another session may be standing in it. Take it first:" \
      "" \
      "    bash .github/scripts/session.sh take" \
      "" \
      "kolonie-docs#318 — four issues were closed claiming work that was on" \
      "somebody else's branch, because nothing between commit and push looked."
  fi

  if claim_is_stale; then
    refuse "The claim on this checkout expired $(claim_age_hours)h ago." \
      "Held by '$CLAIM_AGENT' on branch '$CLAIM_BRANCH'." \
      "If that session is gone, take the checkout again:" \
      "" \
      "    bash .github/scripts/session.sh take"
  fi

  if [ -z "${KOLONIE_AGENT:-}" ]; then
    refuse "KOLONIE_AGENT is not set, so this commit cannot say who made it." \
      "This checkout is held by '$CLAIM_AGENT' on branch '$CLAIM_BRANCH'." \
      "Name yourself and take it:" \
      "" \
      "    export KOLONIE_AGENT=<your-agent-name>" \
      "    bash .github/scripts/session.sh take" \
      "" \
      "kolonie-docs#318 — an unnamed commit is why that incident was" \
      "reconstructable only from a local reflog."
  fi

  if [ "$KOLONIE_AGENT" != "$CLAIM_AGENT" ]; then
    refuse "This checkout is held by another session." \
      "held by : $CLAIM_AGENT   ($(claim_age_hours)h ago, on '$CLAIM_BRANCH')" \
      "you are : $KOLONIE_AGENT" \
      "" \
      "Two sessions in one working copy is kolonie-docs#318. Take a worktree" \
      "of your own — it costs one directory and the branch becomes a property" \
      "of the directory rather than of a shared HEAD:" \
      "" \
      "    git worktree add ../kolonie-docs-$KOLONIE_AGENT" \
      "" \
      "If you know that session is gone:  session.sh take --force"
  fi

  if [ "$branch" != "$CLAIM_BRANCH" ]; then
    refuse "HEAD is not on the branch this session took." \
      "took : $CLAIM_BRANCH" \
      "on   : $branch" \
      "" \
      "Either go back, or take the branch you meant deliberately:" \
      "" \
      "    git switch $CLAIM_BRANCH" \
      "    bash .github/scripts/session.sh take --branch $branch"
  fi

  return 0
}

cmd_take() {
  local agent="" want_branch="" force=no
  while [ $# -gt 0 ]; do
    case "$1" in
      --branch) want_branch=${2:-}; shift 2 ;;
      --force) force=yes; shift ;;
      -*) echo "session.sh take: unknown option $1" >&2; exit 2 ;;
      *) agent=$1; shift ;;
    esac
  done
  [ -n "$agent" ] || agent=${KOLONIE_AGENT:-}
  if [ -z "$agent" ]; then
    refuse "Nobody is taking this checkout." \
      "Name the agent, either in the environment or as an argument:" \
      "" \
      "    export KOLONIE_AGENT=<your-agent-name>" \
      "    bash .github/scripts/session.sh take"
  fi

  local branch default
  branch=$(current_branch)
  default=$(default_branch)

  # A live claim held by somebody else is the incident, so it is refused rather
  # than reported. An expired one is walked over without asking — AGENTS.md §6
  # step 7's rule about abandoned claims, one level down.
  if read_claim && [ "$CLAIM_AGENT" != "$agent" ] && ! claim_is_stale && [ "$force" = no ]; then
    refuse "This checkout is already held by '$CLAIM_AGENT'." \
      "Taken $(claim_age_hours)h ago, on branch '$CLAIM_BRANCH'." \
      "" \
      "A working copy per session is what kolonie-docs#318 asks for:" \
      "" \
      "    git worktree add ../kolonie-docs-$agent" \
      "" \
      "If you know that session is gone:  session.sh take --force"
  fi
  if read_claim && [ "$CLAIM_AGENT" != "$agent" ] && [ "$force" = yes ]; then
    echo "  ! displacing '$CLAIM_AGENT', who took this $(claim_age_hours)h ago on '$CLAIM_BRANCH'."
  fi

  # The branch is the whole of #318, so landing on a leftover one is refused
  # until it is named. `--branch` is one flag and it cannot be done by habit,
  # which is the property the issue asks for.
  if [ "$branch" != "$default" ] && [ "$want_branch" != "$branch" ]; then
    refuse "HEAD is on '$branch', which is not '$default'." \
      "last commit here: $(who_last_touched "$branch")" \
      "" \
      "This is exactly how kolonie-docs#318 happened — a branch another session" \
      "left checked out, read as main by the next one. If you meant it, say so:" \
      "" \
      "    bash .github/scripts/session.sh take --branch $branch" \
      "" \
      "Otherwise:  git switch $default"
  fi

  {
    echo "agent=$agent"
    echo "branch=$branch"
    echo "taken=$(now)"
    echo "pid=$$"
  } > "$CLAIM"

  # `#230` over `#318`: a local identity that already exists is the agent's real
  # one and is worth more than a distinct one this file made up. Only the
  # fall-through to ~/.gitconfig is refused.
  local have_email have_name generated=no
  have_email=$(git config --local --get user.email 2>/dev/null)
  have_name=$(git config --local --get user.name 2>/dev/null)
  if [ -z "$have_email" ]; then
    if [ -n "${KOLONIE_AGENT_EMAIL:-}" ]; then
      have_email=$KOLONIE_AGENT_EMAIL
    else
      have_email="$agent@noreply.kolonie.ai"
      generated=yes
    fi
    git config user.email "$have_email"
  fi
  if [ -z "$have_name" ]; then
    have_name=${KOLONIE_AGENT_NAME:-$agent}
    git config user.name "$have_name"
  fi

  install_hooks

  echo "  ✓ $agent holds this checkout, on '$branch'."
  echo "    commits here are signed $have_name <$have_email>"
  echo "    pre-commit and pre-push will refuse if that stops being true."
  [ "$generated" = no ] || {
    echo
    echo "  ! that address was generated, because this checkout had none set."
    echo "    kolonie-docs#230 wants your GitHub account's noreply address, so"
    echo "    the commit links to the account that made it:"
    echo "      git config user.email '<id>+<handle>@users.noreply.github.com'"
  }
  [ "${KOLONIE_AGENT:-}" = "$agent" ] || {
    echo
    echo "  ! KOLONIE_AGENT is not '$agent' in this shell, and the hooks read it."
    echo "    export KOLONIE_AGENT=$agent"
  }
}

cmd_status() {
  local branch
  branch=$(current_branch)
  if ! read_claim; then
    echo "unclaimed — on '$branch'"
    echo "KOLONIE_AGENT=${KOLONIE_AGENT:-(unset)}"
    return 0
  fi
  echo "held by  : $CLAIM_AGENT"
  echo "on branch: $CLAIM_BRANCH"
  echo "taken    : $(claim_age_hours)h ago$(claim_is_stale && echo "  — EXPIRED (ttl ${TTL_HOURS}h)")"
  echo "HEAD is  : $branch"
  echo "KOLONIE_AGENT=${KOLONIE_AGENT:-(unset)}"
  cmd_check >/dev/null 2>&1 && echo "a commit here would be allowed." || echo "a commit here would be REFUSED — run: session.sh check"
}

cmd_release() {
  if read_claim; then
    rm -f "$CLAIM"
    echo "  ✓ released — '$CLAIM_AGENT' no longer holds this checkout."
  else
    echo "  ✓ nothing to release."
  fi
}

case "${1:-status}" in
  take) shift; cmd_take "$@" ;;
  check) cmd_check ;;
  status) cmd_status ;;
  release) cmd_release ;;
  install-hooks) install_hooks; echo "  ✓ pre-commit and pre-push installed." ;;
  -h|--help|help)
    sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    ;;
  *) echo "session.sh: unknown command '$1' — try --help" >&2; exit 2 ;;
esac
