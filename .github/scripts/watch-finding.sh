#!/bin/bash
# One finding is one issue (`kolonie-docs#237`).
#
# Usage:
#   watch-finding.sh place <identity> <title> <body-file> [--still <sentence>] [label ...]
#   watch-finding.sh resolve <identity> <comment>   # allowlisted findings only
#   watch-finding.sh find <identity>         # the issue carrying it, as JSON, or nothing
#   watch-finding.sh key <identity>          # the marker line, for a body
#
# ## The failure this exists for
#
# Six issues had been filed by the watchers by 2026-08-08 and **three of them
# were the same issue**:
#
#   2026-08-03  #146  The board has stopped maintaining itself
#   2026-08-03  #149  The board has stopped maintaining itself
#   2026-08-06  #179  The board has stopped maintaining itself
#
# Two of them on the same day. **A watcher that files the same thing three times
# teaches its reader to skim** — the first duplicate is noticed, the second is an
# eye-roll, and by the third the watcher's issues are a class of thing you scroll
# past, at which point the one that matters is missed too and nothing about the
# system says so.
#
# ## Why the existing guard did not catch it
#
# All three watchers already looked for an existing issue before filing. Every
# one of them looked with `--state open`. **A finding that was closed and came
# back was therefore invisible**, and filing a second issue was the correct
# behaviour of the code as written. That is the whole bug, and it is why the fix
# is one file instead of three patches: the same line was wrong in three places.
#
# ## The identity, and it is not the title
#
# A machine-readable key, written into the body as a marker and stated in prose
# beside it:
#
#     <!-- watch-finding: silent-service:umami -->
#
# **Not the title**, because a title carries yesterday's numbers and will never
# match tomorrow's, and because a person rewording a title should not silently
# split one finding into two. The key is *the service and the condition* — what
# is wrong and what it is wrong about.
#
# **The key is also printed in the issue body in prose**, deliberately. `#237`
# asks for it: identity by service-and-condition treats *the board has stopped
# maintaining itself, because a workflow failed on Monday* and *…because a
# different one failed on Thursday* as one finding, which is right often enough
# and wrong sometimes. A reader who thinks it has conflated two things can only
# see how if the file says what it joined on.
#
# ## Three cases, three behaviours
#
#   open              comment with today's observation, and nothing else
#   closed, and back  REOPEN it, with a comment saying when it returned
#   absent            file it
#
# **A comment rather than an edit.** The body says what was first seen; the
# comments say it is still true. Editing the body would lose the first
# observation, which is the one that dates the problem.
#
# **Reopening rather than filing.** A recurrence is the same fact, and its
# history is the useful part — *this is the third time since August* is a
# sentence only the reopened issue can say.
#
# ## And a fourth case, for some findings only: it ended (`#351`)
#
#   the condition has measurably stopped   CLOSE it, saying what the number is now
#
# `#328` is why. It reported nine gateway fallbacks in one hour; measured two
# days later the burst had run for three hours and nothing had fallen back since.
# The condition ended before anybody read the issue, and the issue said the same
# thing throughout, because there was no path by which it could say anything
# else. An issue that cannot close is an issue that stops being read, which is
# `#237`'s cost arriving by a different road.
set -uo pipefail

REPO=${GITHUB_REPOSITORY:-Kolonie-AI/kolonie-docs}
RUN_URL=${RUN_URL:-no run url}
LOOKBACK=${WATCH_FINDING_LOOKBACK:-200}

# The marker, in one place, so the writer and the reader cannot disagree about
# its shape. Everything that writes a watcher issue body calls this.
key_line() {
  printf '<!-- watch-finding: %s -->' "$1"
}

# The issue carrying this identity, open **or closed**, newest first.
#
# Listed and filtered here rather than passed to `--search`, for
# `kolonie-docs#150`'s reason: GitHub's issue *index* is eventually consistent
# and an issue filed a moment ago is not searchable yet, while the list endpoint
# answers from the database and is. A run that exits while its own issue is
# invisible is exactly how the next run files the duplicate.
# The filter is piped rather than passed as `--jq`, deliberately. `gh`'s own
# `--jq` would work, and it makes the one line that decides *file or reopen*
# untestable without a stub that reimplements jq — which is a stub that can be
# wrong in the same direction as the code. The script owns its filtering.
find_by_identity() {
  local identity=$1 marker
  marker=$(key_line "$identity")
  gh issue list --repo "$REPO" --state all --limit "$LOOKBACK" \
    --json number,state,title,body |
    jq -r --arg marker "$marker" \
      '[.[] | select(.body != null and (.body | contains($marker)))][0] // empty'
}

cmd_place() {
  local identity=$1 title=$2 body_file=$3
  shift 3
  local still="" labels=()
  while [ $# -gt 0 ]; do
    if [ "$1" = --still ]; then
      still=${2:?place --still needs a sentence}
      shift 2
      continue
    fi
    labels+=("$1")
    shift
  done

  [ -f "$body_file" ] || { echo "no body file at $body_file" >&2; return 2; }

  local found number state still_text
  still_text=${still:-the condition behind this issue is still there.}
  found=$(find_by_identity "$identity")

  if [ -n "$found" ]; then
    number=$(jq -r '.number' <<<"$found")
    state=$(jq -r '.state' <<<"$found")

    if [ "$state" = OPEN ]; then
      rewrite_body "$number" "$identity" "$body_file"
      gh issue comment "$number" --repo "$REPO" --body \
"**Still true today.** $(date -u +%Y-%m-%d): $still_text

Identity: \`$identity\`. [Full run]($RUN_URL)

This is a comment rather than an edit on purpose — the body dates when this was first seen, and these say it has not gone away."
      echo "commented on #$number ($identity)"
      return 0
    fi

    # Closed, and the condition is back. Reopen: a recurrence is the same fact,
    # and the history is the useful part.
    gh issue reopen "$number" --repo "$REPO" >/dev/null
    rewrite_body "$number" "$identity" "$body_file"
    gh issue comment "$number" --repo "$REPO" --body \
"**Reopened — this came back.** $(date -u +%Y-%m-%d): the condition this issue describes is true again, having been closed.

Identity: \`$identity\`. [Full run]($RUN_URL)

Reopened rather than filed again, so that how often this recurs stays readable in one place. If it is back for a *different* underlying reason, that is worth a comment saying so — see what the identity joins on, in the body."
    echo "reopened #$number ($identity)"
    return 0
  fi

  local args=(--repo "$REPO" --title "$title" --body-file "$body_file")
  for label in ${labels+"${labels[@]}"}; do args+=(--label "$label"); done
  gh issue create "${args[@]}"
  echo "filed a new issue ($identity)"
  # A visibility wait that gives up is a warning, not a failed run: the issue
  # *was* filed, and failing here would send the caller down its error path over
  # a successful write.
  await_visible "$identity" || true
}

# **Which findings may close themselves is an allowlist, not a default**
# (`kolonie-docs#351`).
#
# A finding that *can* resolve itself and one that *must not* are different
# kinds, and the difference is whether the condition is deterministic. *Were
# there N fallbacks in an hour* is a number, and *there have been none since* is
# the same number answering the other way. **A model's reading of an error line
# is not**, and whether that has been dealt with is a person's call — a watcher
# that could close it is the thing this must not become.
#
# So the list is a constant and not an environment variable: a knob that widens
# it is a knob that widens it by accident, at 06:00, in a workflow nobody is
# reading. A new entry is a line in this file, in a diff somebody reviewed.
RESOLVABLE_IDENTITIES="gateway-not-serving"

is_resolvable() {
  local one
  for one in $RESOLVABLE_IDENTITIES; do
    [ "$one" = "$1" ] && return 0
  done
  return 1
}

# **The condition has ended, so say so and close it** (`#351`).
#
# Three properties, and the second and third are what make it safe to run on a
# timer:
#
#   - it refuses an identity that is not on the allowlist, **loudly and
#     non-zero**, rather than quietly doing nothing — a caller that has added a
#     `resolve` for a model-judged finding must find out at the first run
#   - with no open issue of that identity it writes nothing and exits 0. Every
#     ordinary day is that case: the gateway serves everything, and a watcher
#     that treated *nothing to close* as a failure would be red every day it had
#     nothing to say
#   - it closes and does not delete, so the reopen path in `cmd_place` is what
#     handles the condition coming back — one issue, still, with its recurrences
#     readable in one place
cmd_resolve() {
  local identity=$1 comment=$2 found number state

  if ! is_resolvable "$identity"; then
    echo "refusing to resolve $identity: it is not on the allowlist ($RESOLVABLE_IDENTITIES)." >&2
    echo "A finding may close itself only where the condition is a measurement with a precise end. If this one is, add it to RESOLVABLE_IDENTITIES in watch-finding.sh, in a diff somebody reads." >&2
    return 2
  fi

  found=$(find_by_identity "$identity")
  [ -n "$found" ] || { echo "no issue carries $identity — nothing to resolve"; return 0; }

  number=$(jq -r '.number' <<<"$found")
  state=$(jq -r '.state' <<<"$found")
  [ "$state" = OPEN ] || { echo "#$number ($identity) is already closed — nothing to resolve"; return 0; }

  gh issue comment "$number" --repo "$REPO" --body \
"**Resolved — the condition has ended.** $(date -u +%Y-%m-%d): $comment

Identity: \`$identity\`. [Full run]($RUN_URL)

Closed by the watcher that filed it, because this condition is a measurement with a precise end rather than a judgement about what a log line meant. **The end is the same measurement that filed this, read the other way** — not a second, lower threshold, which would flap.

If the condition returns, **this issue is reopened** rather than filed again, so how often it recurs stays readable here."
  gh issue close "$number" --repo "$REPO" >/dev/null
  echo "resolved #$number ($identity)"
}

# **The body is a reference, so it is rewritten in place** (`kolonie-docs#315`).
#
# ## What it cost to not do this
#
# `red-on-main.yml` reopened `#285` on 2026-08-12 over a failure in `Triage
# inbound`, while its body still read *"Check Red Lines — last completed run on
# `main` failed"*. That workflow had been green since the day before. The issue
# was claimed and worked twice: once against `Check Red Lines`, and once against a
# completely different cause, with the body still naming the first.
#
# ## Why here and not in each caller
#
# `AGENTS.md` §3 is the rule and it is not about reopens: *"a file that is
# appended to and never rewritten is a chronicle. Anything read as a reference is
# rewritten in place."* An issue body is a reference — a reader arrives and looks
# something up — and the comments are the chronicle, which they already do well.
# Every caller here builds its body from the measurement it has just taken, so
# every one of them was throwing away the current answer on every path but the
# first. `#315` names the reopen because that is where it was caught.
#
# **The comments are untouched.** How often a condition recurs staying readable in
# one place is the point of reusing the issue, and that is what they carry.
#
# ## The one thing that could go wrong, refused rather than trusted
#
# The identity marker lives *in the body*, so a rewrite that dropped it would make
# the issue unfindable and the next run would file a duplicate — the exact failure
# this whole file exists against. So a body with no marker is not written, and the
# run says so instead of failing: the comment below is still worth having, and a
# stale body is better than a lost issue.
rewrite_body() {
  local number=$1 identity=$2 body_file=$3

  if ! grep -qF "$(key_line "$identity")" "$body_file"; then
    echo "refusing to rewrite #$number: the new body carries no $identity marker" >&2
    return 0
  fi

  gh issue edit "$number" --repo "$REPO" --body-file "$body_file" >/dev/null &&
    echo "rewrote the body of #$number ($identity)"
}

VISIBILITY_ATTEMPTS=${VISIBILITY_ATTEMPTS:-30}
VISIBILITY_POLL=${VISIBILITY_POLL:-2}

# **Wait until the issue we just filed can be found** (`kolonie-docs#150`, kept
# through `#237`'s refactor rather than quietly dropped).
#
# Each of the three watchers had this guard and each had it separately. It stays
# because the failure it prevents is precisely the one this whole file is about:
# a run that exits while its own issue is still invisible is how the *next* run
# files the duplicate. Consolidating three copies of a guard is not a reason to
# end up with none.
#
# Bounded and loud. A hang would be worse than a duplicate, and a silent give-up
# would be worse than both.
await_visible() {
  local identity=$1 attempt=0 seen
  while [ "$attempt" -lt "$VISIBILITY_ATTEMPTS" ]; do
    seen=$(find_by_identity "$identity")
    if [ -n "$seen" ]; then
      echo "findable as #$(jq -r '.number' <<<"$seen") after $((attempt * VISIBILITY_POLL))s"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep "$VISIBILITY_POLL"
  done
  echo "::warning::the issue just filed for $identity was still not findable after $((VISIBILITY_ATTEMPTS * VISIBILITY_POLL))s — the next run may file a duplicate"
  return 1
}

# The paragraph every watcher issue ends with, in one place so that three
# workflows cannot drift into three slightly different accounts of the same
# machinery (`#237`).
#
# It has to say four things, and the third is the one a reader will otherwise
# guess wrong: it was filed by a machine; it will comment here again rather than
# open a second issue; **closing it is what tells the machine the condition was
# handled**; and what the identity joins on, so somebody who thinks two different
# problems have been merged into one can see exactly how.
# **And the footer has to say which kind of finding this is** (`#351`). *Closing
# this is how you tell the machine it was handled* was true of every finding
# until one of them could close itself; on a resolvable one it now understates
# what the machine does, and a reader who closed it expecting that to be the only
# path would be wrong about what happens tomorrow. The sentence is derived from
# the allowlist rather than passed in, so the two cannot disagree.
cmd_footer() {
  local identity=$1 joins_on=$2 workflow=$3 handled
  if is_resolvable "$identity"; then
    handled="**This one also closes itself when the condition ends**, because it is a
measurement with a precise end rather than a judgement — and the end is the same
measurement that filed it, read the other way. Closing it by hand is still the
way to say *handled*; if the condition is still true tomorrow it reopens."
  else
    handled="**Closing this is how you tell the machine it was handled.** Nothing else does."
  fi
  cat <<FOOTER
$(key_line "$identity")

---

**Filed by a machine.** \`$workflow\` opened this; nobody read it first. While the
condition holds it will **comment here** rather than open a second issue, and if
this is closed and the condition returns it will **reopen this one** — so how
often it recurs stays readable in one place.

$handled

**What it treats as "the same finding":** $joins_on — recorded as \`$identity\`.
That is right often enough and wrong sometimes: two different underlying causes
can share it and would arrive here as one issue. If you think that has happened,
say so in a comment — the identity is written down precisely so the join can be
argued with rather than guessed at.
FOOTER
}

case "${1:-}" in
  key)    shift; key_line "${1:?key needs an identity}"; echo ;;
  find)   shift; find_by_identity "${1:?find needs an identity}" ;;
  footer) shift; cmd_footer "${1:?footer needs an identity}" "${2:?footer needs what it joins on}" "${3:?footer needs a workflow name}" ;;
  place) shift; cmd_place "${1:?place needs an identity}" "${2:?place needs a title}" "${3:?place needs a body file}" "${@:4}" ;;
  resolve) shift; cmd_resolve "${1:?resolve needs an identity}" "${2:?resolve needs a comment saying what the measurement now is}" ;;
  *)     echo "usage: watch-finding.sh place <identity> <title> <body-file> [--still <sentence>] [label ...] | resolve <identity> <comment> | find <identity> | key <identity> | footer <identity> <joins-on> <workflow>" >&2; exit 2 ;;
esac
