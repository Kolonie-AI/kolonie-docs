#!/bin/bash
# What is waiting, and what nothing will come and take (#265, #381, #391).
#
# Three findings, one list: the issues no scheduler will ever hand to anybody
# (`#265`), the claims nobody is behind (`#381`), and the issues held for a
# member to clear (`#391`). They are three questions with three answers, so they
# are three sections — and one file, because they are read by the same person at
# the same moment, and a second daily message is a message nobody opens.
#
# Usage:
#   waiting-list.sh entries          # -> one TSV row per waiting issue
#   waiting-list.sh body <entries>   # -> the markdown list, packages grouped
#   waiting-list.sh arrivals <old-body> <entries>  # -> the issues not in the old body
#
# ## Why this exists
#
# `agent:opencode` has a worker that comes and takes things. `agent:claude` and
# `agent:human` have nobody: the label says a development agent or a person
# should do it, and until now nothing told anyone that one was waiting. That
# worked while the maintainer agent was in the conversation when the label was
# applied, and stops working the moment `kolonie-docs#262` applies it at 03:20 on
# a Sunday.
#
# ## Why a list and not a queue
#
# `#265`, and it is the design constraint rather than an aside: a Claude agent
# takes a *package* and asks questions mid-work. It is not something a scheduler
# hands one issue to, the way the opencode worker is handed one. So what this
# produces is a list for the person deciding what to start, and its whole job is
# to make sure a routed issue is never merely labelled and forgotten.
#
# ## Where it goes, and why not mail
#
# `#265` offers two homes — the operator mail path, or a single issue kept up to
# date. **There is no operator mail path in this repository** (checked
# 2026-08-10: nothing in `.github/workflows/` sends any), so a mailed list would
# have meant a new credential in an issue that is not about credentials. One
# issue, rewritten in place, needs none: the body is the current list, and a
# comment is written only when the list has changed — which is what reaches
# somebody's notifications.
#
# **Not a comment per issue.** That is a notification per routing decision, and
# the point is a list somebody can act on in one sitting.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

ORG=${ORG:-Kolonie-AI}

# The two labels this reports on. `agent:opencode` is deliberately absent: it has
# a worker, and a list of things already being taken is the daily message nobody
# opens.
WAITING_LABELS=${WAITING_LABELS:-agent:claude agent:human}

# The columns that mean *somebody already has this*. Everything else — Inbox,
# Ready, Blocked — is waiting for somebody, and a `blocked:human` issue
# in Blocked is exactly what the `agent:human` half of this list is for.
# Pipe separated rather than an array, because an array cannot come in from the
# environment and every other setting in this file can.
HELD_STATUSES=${HELD_STATUSES:-In Progress|In Review|Done}

# No `BOARD_LIMIT`. `board-read` follows `pageInfo` to the end, so there is no
# number here to be sized wrongly — which was the whole point of `#269`: a limit
# that is too small drops issues off the queue silently.
SEARCH_LIMIT=${SEARCH_LIMIT:-200}

# The issue this list is published on. It is excluded from its own list, which
# is not a special case worth avoiding — it carries no `agent:` label, and this
# is belt and braces for the day somebody labels it.
LIST_ISSUE=${LIST_ISSUE:-}

# The route written on a stuck In Progress card (`kolonie-docs#381`). It is not a
# label and never will be: nothing applies it, nothing reads it off an issue, and
# it exists so that one TSV can carry two kinds of row without `arrivals` or the
# workflow having to learn a second shape.
STUCK_ROUTE=${STUCK_ROUTE:-stuck:in-progress}

# The hold only a member lifts (`kolonie-docs#389`), and the sentinel route a
# held row carries (`#391`). Same trick as `STUCK_ROUTE` above and for the same
# reason: one TSV, three kinds of row, and neither `arrivals` nor the workflow
# has to learn a second shape to carry the third one.
CLEARANCE_LABEL=${CLEARANCE_LABEL:-needs-clearance}
CLEARANCE_ROUTE=${CLEARANCE_ROUTE:-held:needs-clearance}

die() {
  echo "$1" >&2
  exit "${2:-1}"
}

# Why this is not `agent:opencode`, in one clause (`#265`).
#
# **Read off the labels, and only off the labels.** Triage (`#262`) does not yet
# record its reasoning anywhere a script can read, so the honest options were a
# clause derived from what is on the issue or a sentence invented to look like
# one. When triage does record a reason, this is the one function that has to
# change.
why_waiting() {
  local labels=$1 route=$2
  case " $labels " in
    *" blocked:human "*)      echo "waits on a person: one of the seven classes in AGENTS.md §5" ;;
    *" opencode:forbidden "*) echo "the worker may not write it — its implementation is a path its own rules forbid" ;;
    *" opencode:failed "*)    echo "the worker tried it and did not finish" ;;
    *" decision "*)           echo "a decision has to be made before code can be written" ;;
    *" idea "*)               echo "not specified well enough for an unattended run" ;;
    *)
      if [ "$route" = "agent:human" ]; then
        echo "routed to a person"
      else
        echo "routed to a Claude agent, which is the safe default when triage is unsure"
      fi
      ;;
  esac
}

# The claims nobody is behind, in the same eight columns (`kolonie-docs#381`).
#
# ## Why the daily list is where this belongs
#
# The worker's own sweep says it on the issue every four hours, and that is the
# right place for a run that died — somebody will come back to it. It is the
# wrong place for a claim nobody is coming back to at all: after a day the issue
# has five identical comments on it and the one person who could move the card
# has never been told. This list is read by that person, and it is one page
# however often the run behind it fires.
#
# ## Why it is computed from the board and nothing else
#
# One step holds one `GH_TOKEN` and this one holds the board app's, which is
# Projects-only. So the whole finding — how long the card has sat, and how many
# issues are queued behind it — comes off the board, and no issue is read. That
# is what `forgotten-claims --escalated` is: the board half, on its own.
stuck() {
  # The board the caller has already read, or empty to read one. An empty string
  # is exactly what `BOARD_FILE` means to the worker — *no hand-over, ask for
  # yourself* — so the two cases need no branch here.
  local board=$1 repo number hours queued title cost

  # The exit code is not read as *nothing is stuck*. A board that could not be
  # read and a board with nothing stuck on it arrive here identically, and
  # reporting them the same way is the failure this whole workflow exists to
  # prevent — one applied to itself.
  local found
  found=$(BOARD_FILE="$board" bash "$HERE/opencode-worker.sh" \
    forgotten-claims --escalated 2>/dev/null) ||
    die "the In Progress cards could not be read, so the list would understate what is stuck"

  [ -n "$found" ] || return 0

  while IFS=$'\t' read -r repo number hours queued title; do
    [ -n "${repo:-}" ] || continue
    case "$queued" in
      0) cost="nothing else in that repository is queued behind it" ;;
      1) cost="1 issue in that repository is queued behind it" ;;
      *) cost="$queued issues in that repository are queued behind it" ;;
    esac
    # Rank 0, and `created` left empty: this row is not sorted against the
    # labelled ones and has no creation date of its own to sort by — what it has
    # is the age of the *card*, which is in the sentence.
    printf '%s\t%s\t%s\t0\t\t\tIn Progress for %s hours with nothing behind it; %s\t%s\n' \
      "$repo" "$number" "$STUCK_ROUTE" "$hours" "$cost" "$title"
  done <<<"$found"
}

# Whole days since an ISO timestamp, floored. A timestamp that cannot be parsed
# is 0 rather than an error: the row is worth having without its age, and the
# sentence beside it says which age it is measuring.
days_since() {
  local began now
  began=$(date -u -d "$1" +%s 2>/dev/null) || { echo 0; return 0; }
  now=$(date -u +%s)
  echo $(( (now - began) / 86400 ))
}

# A number of days as somebody reads it.
spell_days() {
  case "$1" in
    0) echo "less than a day" ;;
    1) echo "1 day" ;;
    *) echo "$1 days" ;;
  esac
}

# When the hold went on, or nothing at all when the timeline cannot be read.
#
# **`last`, not `first`.** A label taken off and put back on is held from the
# second time — reporting the first would age a fresh hold by however long the
# earlier one lasted, which is the one number on this section somebody acts on.
held_since() {
  gh api "repos/$1/issues/$2/timeline" --paginate \
    --jq "[.[] | select(.event == \"labeled\" and .label.name == \"$CLEARANCE_LABEL\")
           | .created_at] | last // empty" 2>/dev/null | tail -1
}

# What is waiting for a person to clear, in the same eight columns (`#391`).
#
# ## Why it is on this list rather than in a workflow of its own
#
# `#389` puts `needs-clearance` on an issue from outside the organisation and
# `#390` keeps a held issue out of Ready. Both are machinery, and neither tells
# anybody the hold is there — so a held issue does not merely sit, it sits
# **invisibly**, because Inbox is also where undecided work lives. This workflow
# already answers that question one door along, in the shape the answer needs:
# one issue rewritten in place, and a comment only when the set changed.
#
# ## Why the age is looked up per issue
#
# *2 waiting for your clearance, oldest 6 days* gets somebody out of their chair
# and *2 waiting* does not, so the age is the half that does the work. A search
# cannot say when a label went on, so the timeline is read once per held issue —
# one call each, on a set that is small by construction, six times a day.
#
# **A timeline that cannot be read does not lose the row.** The entry falls back
# to how long the issue has been *open* and says so in as many words, because an
# age that is quietly the wrong age is worse than one that names what it measured.
clearance() {
  local found rows repo number author created title since age measured

  found=$(gh search issues --owner "$ORG" --state open --label "$CLEARANCE_LABEL" \
    --limit "$SEARCH_LIMIT" --json repository,number,title,createdAt,author) ||
    die "the held issues could not be searched, so the list would understate what waits for a person"
  [ -n "$found" ] || return 0

  rows=$(jq -r --arg list "$LIST_ISSUE" '
    [ .[]
      | { repo: .repository.nameWithOwner, number: .number, title: .title,
          createdAt: .createdAt, author: (.author.login // "somebody") }
      | select("\(.repo)#\(.number)" != $list) ]
    | .[]
    | [.repo, (.number|tostring), .author, .createdAt, .title]
    | @tsv
  ' <<<"$found") || die "the held issues could not be read"

  [ -n "$rows" ] || return 0

  {
    while IFS=$'\t' read -r repo number author created title; do
      [ -n "${repo:-}" ] || continue
      since=$(held_since "$repo" "$number")
      if [ -n "$since" ]; then
        age=$(days_since "$since")
        measured="held for $(spell_days "$age")"
      else
        since=$created
        age=$(days_since "$since")
        measured="open for $(spell_days "$age"), and when the hold went on could not be read"
      fi
      # **Column four carries the age in days and not a rank.** A held row is
      # never sorted against the labelled ones, and the heading needs one number
      # a reader of the file can take without parsing an English sentence.
      #
      # **The author in a code span and never as `@name`.** This line is written
      # into an issue body once a day, and a plain mention would notify whoever
      # opened the issue every single time the list is rewritten.
      printf '%s\t%s\t%s\t%s\t%s\t\topened by `%s`, %s\t%s\n' \
        "$repo" "$number" "$CLEARANCE_ROUTE" "$age" "$since" \
        "$author" "$measured" "$title"
    done <<<"$rows"
  } | sort -t$'\t' -k4,4nr
}

# The two findings that are not labelled work, in one call because every way out
# of `entries` needs both of them (`#381`, `#391`). A section reachable only when
# something else happened to be waiting is a section nobody can rely on.
extras() {
  clearance
  stuck "$1"
}

# One row per waiting issue: repo, number, route, rank, created, blockers (space
# separated, `owner/repo#n`), why, title.
entries() {
  local label board issues found
  # **One search per label, and not one search with two.** Measured 2026-08-10:
  # `gh search issues --label agent:claude --label agent:human` returns **zero**,
  # because two `label:` qualifiers are an AND in GitHub's search syntax and no
  # issue carries both. A list that is empty for a reason nobody can see is the
  # failure this whole issue is about, so the labels are asked for one at a time
  # and the answers merged here.
  board=""
  issues='[]'
  for label in $WAITING_LABELS; do
    found=$(gh search issues --owner "$ORG" --state open --label "$label" \
      --limit "$SEARCH_LIMIT" --json repository,number,title,createdAt,labels) ||
      die "the issues labelled $label could not be searched, so the list would be wrong"
    [ -n "$found" ] || found='[]'
    issues=$(jq -s 'add | unique_by("\(.repository.nameWithOwner)#\(.number)")' \
      <(printf '%s' "$issues") <(printf '%s' "$found")) ||
      die "the labelled issues could not be merged"
  done

  # **The search is what fails first on a broken credential, and it stays that
  # way.** The board read below could equally be moved above it — the stuck
  # section needs no labelled issue — but then a run with no `gh` at all would
  # report *the board could not be read* about a failure that is really the
  # search, and the message a red run leaves is most of what it is worth.
  if [ -z "$issues" ] || [ "$(jq 'length' <<<"$issues")" -eq 0 ]; then
    extras ""
    return 0
  fi

  board=$(mktemp)
  trap 'rm -f "$board"' RETURN
  # `board-read` and not `gh project item-list`: the same document for 2 points
  # against 203 (`#269`, measured 2026-08-10 on a 129-item board). Same
  # `.items[]`, same `.status`, same `.content` — so the `jq` below is unchanged.
  bash "$HERE/opencode-worker.sh" board-read \
    >"$board" || die "the board could not be read, so no column can be trusted"

  # `--slurpfile` and not `--argjson`: the board is one document of every item in
  # the project, and `execve` caps a single argument at 128 KiB whatever `ARG_MAX`
  # says. The worker learned that the hard way on 2026-08-07.
  local held_json rows
  held_json=$(jq -Rc 'split("|")' <<<"$HELD_STATUSES")

  rows=$(jq -r --slurpfile board "$board" --argjson held "$held_json" \
    --arg list "$LIST_ISSUE" '
    [ .[]
      | { repo: .repository.nameWithOwner,
          number: .number,
          title: .title,
          createdAt: .createdAt,
          labels: [.labels[].name] }
      | select("\(.repo)#\(.number)" != $list)
      | . as $issue
      | (($board[0].items[]
          | select(.content.number == $issue.number
                   and .content.repository == $issue.repo)
          | .status) // "not on the board") as $status
      | select($held | index($status) | not)
      | $issue + {
          status: $status,
          route: (if ($issue.labels | index("agent:human")) then "agent:human"
                  else "agent:claude" end),
          rank: (if ($issue.labels | index("p1")) then 0
                 elif ($issue.labels | index("p2")) then 1
                 else 2 end) }
    ]
    | sort_by(.rank, .createdAt)
    | .[]
    | [.repo, (.number|tostring), .route, (.rank|tostring), .createdAt,
       (.labels | join(" ")), .status, .title]
    | @tsv
  ' <<<"$issues") || die "the labelled issues could not be read"

  if [ -z "$rows" ]; then
    extras "$board"
    return 0
  fi

  # The blockers are asked for one issue at a time, which is one call each and a
  # list this size is fifteen of them per run, six times a day (`#409`) — still
  # less than the worker spends before lunch. An issue whose blockers cannot
  # be read is still reported — a missing dependency line is worse than nothing
  # only if it is silent, so it says so in the entry.
  local repo number route rank created labels status title waits why
  while IFS=$'\t' read -r repo number route rank created labels status title; do
    [ -n "${repo:-}" ] || continue
    # **The worker's `blockers`, not a second copy of it.** What an issue waits
    # for has one definition (`#261`) and this is not the place to write it
    # again — a second copy is the failure mode §4 rejects for a status label.
    waits=$(bash "$HERE/opencode-worker.sh" blockers "$repo" "$number" 2>/dev/null |
      tr '\n' ' ' | sed 's/ $//') || waits="(unreadable)"
    why=$(why_waiting "$labels" "$route")
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$repo" "$number" "$route" "$rank" "$created" "$waits" "$why" "$title"
  done <<<"$rows"

  # **After the labelled rows and never mixed into them.** A stuck card is not
  # waiting to be started — somebody started it — and a held one may not be
  # started at all: three different questions with three different answers, and
  # `body` gives each of them its own section.
  extras "$board"
}

# The markdown, with a package as one entry (`#265`).
#
# **A package is not a second record.** `#261` made a dependency a relation the
# machine can read, and `#259` says a package is what `agent:claude` is for — so
# a set of issues linked by dependency already *is* a package, and this only has
# to notice. Issues linked to each other appear under one heading, blockers
# first, because that is the order they will be worked in.
body() {
  local file=$1
  [ -f "$file" ] || die "body needs the file that \`entries\` wrote, and $file is not one" 1

  # **When this was read, in the body itself** (`#409`). Every entry below was
  # open at that minute and can be closed at the next one; there is no cheaper
  # way to know than to ask, and asking is a run. A reader who can see the age
  # of the list can decide what to do about it, which is the whole of what the
  # old wording — *rewritten daily*, and nothing about when — took away.
  local read_at
  read_at=$(date -u '+%Y-%m-%d %H:%M UTC')

  if [ ! -s "$file" ]; then
    printf '%s\n' "Nothing is waiting for a Claude agent or for a person right now." \
      "" \
      "**Nothing is waiting for your clearance either.** No open issue carries \`$CLEARANCE_LABEL\` (\`kolonie-docs#391\`)." \
      "" \
      "Read at $read_at and rewritten every four hours by \`.github/workflows/waiting-for-an-agent.yml\` (\`kolonie-docs#265\`, \`#409\`). It comments only when the list changes, so an unread notification here always means something arrived."
    return 0
  fi

  awk -F'\t' -v stuck_route="$STUCK_ROUTE" -v held_route="$CLEARANCE_ROUTE" \
      -v clearance_label="$CLEARANCE_LABEL" -v read_at="$read_at" '
    # **The stuck rows are taken out first and counted separately** (`#381`).
    # They are not waiting to be started, so folding them into the headline would
    # make the one number on this list mean two things — and folding them into
    # the package union would let a card nobody is behind pull an unrelated
    # package under its heading.
    $3 == stuck_route {
      stuck_key[++stuck_count] = $1 "#" $2
      stuck_repo[stuck_count] = $1; stuck_number[stuck_count] = $2
      stuck_why[stuck_count] = $7; stuck_title[stuck_count] = $8
      next
    }
    # **And the held rows are taken out for the same reason** (`#391`). A held
    # issue is not waiting to be started by anybody — it may not be started at
    # all until a member lifts the label — so counting it in the headline would
    # make the one number on this list mean a third thing.
    $3 == held_route {
      held_repo[++held_count] = $1; held_number[held_count] = $2
      held_age[held_count] = $4 + 0
      held_why[held_count] = $7; held_title[held_count] = $8
      if ($4 + 0 > held_oldest) held_oldest = $4 + 0
      next
    }
    {
      key = $1 "#" $2
      order[++count] = key
      repo[key] = $1; number[key] = $2; route[key] = $3
      waits[key] = $6; why[key] = $7; title[key] = $8
      # Every issue starts in a package of its own; a link merges two.
      root[key] = key
    }
    function spell(d) { return d == 0 ? "less than a day" : (d == 1 ? "1 day" : d " days") }
    function find(k) { while (root[k] != k) { root[k] = root[root[k]]; k = root[k] } return k }
    function union(a, b,  ra, rb) { ra = find(a); rb = find(b); if (ra != rb) root[rb] = ra }
    END {
      # A link counts only when both ends are on this list. A blocker that is
      # somebody else s work is named in the entry, not folded into the package.
      for (i = 1; i <= count; i++) {
        k = order[i]
        n = split(waits[k], w, " ")
        for (j = 1; j <= n; j++) if (w[j] in root) union(w[j], k)
      }

      if (count > 0)
        print "**" count " issue(s) are waiting for somebody to start them.** The opencode worker will not take any of these; that is what the label means."
      else
        print "**Nothing is waiting for a Claude agent or for a person right now.**"
      print ""

      for (i = 1; i <= count; i++) {
        k = order[i]
        r = find(k)
        if (seen[r]++) continue

        members = 0
        for (j = 1; j <= count; j++) if (find(order[j]) == r) member[++members] = order[j]

        if (members > 1) {
          printf "### A package of %d, in this order\n\n", members
        } else {
          print "###", title[k]
          print ""
        }

        for (j = 1; j <= members; j++) {
          m = member[j]
          if (members > 1)
            printf "%d. [`%s#%s`](https://github.com/%s/issues/%s) — %s\n", \
              j, repo[m], number[m], repo[m], number[m], title[m]
          else
            printf "- [`%s#%s`](https://github.com/%s/issues/%s)\n", \
              repo[m], number[m], repo[m], number[m]
          printf "   - `%s` — %s\n", route[m], why[m]
          if (waits[m] != "") printf "   - waits for %s\n", waits[m]
        }
        print ""
      }

      # **The section a person is the only one who can end** (`#391`). While
      # `needs-clearance` is on an issue it goes nowhere — both workers take work
      # from Ready and a held issue is never moved there (`#390`) — and it goes
      # nowhere in **Inbox**, which is also where undecided work lives. So it is
      # not visibly waiting for anything, and this line is the whole of what
      # tells anybody it is there.
      #
      # **It is printed on a day when nothing is held too**, as a sentence. An
      # empty heading reads as a section that broke; a sentence reads as an
      # answer, and this file already draws that distinction for the list itself.
      print "---"
      print ""
      if (held_count > 0) {
        printf "## %d waiting for your clearance, oldest %s\n\n", held_count, spell(held_oldest)
        print "These carry `" clearance_label "`, and **only a member of the organisation takes that off** (`kolonie-docs#389`). While it is on, the card is held out of **Ready** and neither worker will pick the issue up (`kolonie-docs#390`) — so nothing here is queued behind anything except a person looking at it. Taking the label off leaves nothing behind: the next triage pass treats the issue exactly as it would any other."
        print ""
        for (i = 1; i <= held_count; i++) {
          printf "- [`%s#%s`](https://github.com/%s/issues/%s) — %s\n", \
            held_repo[i], held_number[i], held_repo[i], held_number[i], held_title[i]
          printf "   - %s\n", held_why[i]
        }
        print ""
      } else {
        print "**Nothing is waiting for your clearance.** No open issue carries `" clearance_label "` right now, so there is nothing here for a member to lift (`kolonie-docs#391`)."
        print ""
      }

      # **The section that is not work to be started** (`#381`). A card that has
      # been In Progress for over a day is holding its whole repository out of
      # the opencode queue, and the worker has been saying so on the issue every
      # four hours to nobody. This is the one page the person who can move it
      # actually reads.
      if (stuck_count > 0) {
        print "---"
        print ""
        print "## " stuck_count " claim(s) nobody is behind"
        print ""
        print "These are **In Progress** and have not moved in over a day. Nothing here is being taken away from anybody — but while a card sits in In Progress, `pick` skips every other issue in its repository (`kolonie-docs#266`), so one forgotten claim stops a whole repository. If it is yours, it is yours; if it is not, moving it to **Ready** starts that repository again."
        print ""
        for (i = 1; i <= stuck_count; i++) {
          printf "- [`%s#%s`](https://github.com/%s/issues/%s) — %s\n", \
            stuck_repo[i], stuck_number[i], stuck_repo[i], stuck_number[i], stuck_title[i]
          printf "   - %s\n", stuck_why[i]
        }
        print ""
      }

      print "---"
      print ""
      print "**Read at " read_at "**, and rewritten every four hours by `.github/workflows/waiting-for-an-agent.yml` (`kolonie-docs#265`, `#409`). This is a reading and not a live view: an issue above may have been closed since, so check the state of one before you build a package around it. A comment appears only when this list changes, so a notification here is always something new. A package is a set of issues linked by GitHub'"'"'s dependency relation (`kolonie-docs#261`) — it is one entry because it is one piece of work."
    }
  ' "$file"
}

# The issues on the new list that the old body did not carry (`#265`).
#
# The old *body* rather than a stored list, because the body is already the
# record and a second one would go stale against it — the same argument §4 makes
# for the board being the only place a status lives.
arrivals() {
  local old=$1 file=$2
  [ -f "$file" ] || die "arrivals needs the file that \`entries\` wrote" 1

  local repo number rest
  while IFS=$'\t' read -r repo number rest; do
    [ -n "${repo:-}" ] || continue
    if [ ! -f "$old" ] || ! grep -qF "$repo#$number" "$old"; then
      printf '%s#%s\n' "$repo" "$number"
    fi
  done < "$file"
}

case "${1:-}" in
  entries)
    entries
    exit 0
    ;;

  body)
    body "${2:?body needs the file that \`entries\` wrote}"
    exit 0
    ;;

  arrivals)
    arrivals "${2:?arrivals needs the previous body}" \
      "${3:?arrivals needs the file that \`entries\` wrote}"
    exit 0
    ;;

  *)
    die "usage: waiting-list.sh entries | body <entries> | arrivals <old-body> <entries>"
    ;;
esac
