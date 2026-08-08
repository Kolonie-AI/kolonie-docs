#!/bin/bash
# One finding is one issue (`kolonie-docs#237`).
#
# Usage:
#   watch-finding.sh place <identity> <title> <body-file> [label ...]
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
  local labels=("$@")

  [ -f "$body_file" ] || { echo "no body file at $body_file" >&2; return 2; }

  local found number state
  found=$(find_by_identity "$identity")

  if [ -n "$found" ]; then
    number=$(jq -r '.number' <<<"$found")
    state=$(jq -r '.state' <<<"$found")

    if [ "$state" = OPEN ]; then
      gh issue comment "$number" --repo "$REPO" --body \
"**Still true today.** $(date -u +%Y-%m-%d): the condition behind this issue is still there.

Identity: \`$identity\`. [Full run]($RUN_URL)

This is a comment rather than an edit on purpose — the body dates when this was first seen, and these say it has not gone away."
      echo "commented on #$number ($identity)"
      return 0
    fi

    # Closed, and the condition is back. Reopen: a recurrence is the same fact,
    # and the history is the useful part.
    gh issue reopen "$number" --repo "$REPO" >/dev/null
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
cmd_footer() {
  local identity=$1 joins_on=$2 workflow=$3
  cat <<FOOTER
$(key_line "$identity")

---

**Filed by a machine.** \`$workflow\` opened this; nobody read it first. While the
condition holds it will **comment here** rather than open a second issue, and if
this is closed and the condition returns it will **reopen this one** — so how
often it recurs stays readable in one place.

**Closing this is how you tell the machine it was handled.** Nothing else does.

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
  *)     echo "usage: watch-finding.sh place <identity> <title> <body-file> [label ...] | find <identity> | key <identity> | footer <identity> <joins-on> <workflow>" >&2; exit 2 ;;
esac
