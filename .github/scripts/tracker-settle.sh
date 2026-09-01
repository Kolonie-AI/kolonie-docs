#!/bin/bash
# Close a package tracker whose every manifested child is verified delivered.
# `kolonie-docs#566`.
#
# Usage:
#   tracker-settle.sh              # close what is verified, report what is not
#   tracker-settle.sh --dry-run    # say what it would do, write nothing
#
# ## The state this ends
#
# `kolonie-platform#1754` had all fourteen of its children closed — the last of
# them, `kolonie-workplace#105`, delivered by pull request `#107` merged with
# every required check green — and sat in Blocked for two days. Nothing was
# wrong with the work; there was no path by which the board could say so.
#
# ## Why it is opt-in, and why the marker is not a word
#
# **It closes an issue, which is the one write on this board nobody can undo by
# reading it.** A rule that inferred *tracker* from the word *Epic*, a checklist
# or a prose table would decide that about issues whose authors never asked it
# to — and a wrong close is invisible afterwards, because a closed issue leaves
# the queue. So an issue is eligible only when its body carries
#
#     <!-- package-tracker -->
#
# and each binding child is named by its own machine-readable line:
#
#     <!-- tracker-child: https://github.com/OWNER/REPO/issues/N -->
#     <!-- tracker-child: https://github.com/OWNER/REPO/issues/N no-code -->
#
# A URL is what makes a child cross-repository without a convention about which
# repository a bare number means. `no-code` is the explicit way to say a child
# is a decision or a close-out that no pull request delivers — explicit, because
# *this one needed no code* is exactly the judgement a settlement pass must not
# make for somebody.
#
# ## What it verifies, and what it does when it cannot
#
# Every child must be `CLOSED`, and every child not marked `no-code` must have a
# pull request that is **merged** with its checks **green**. Anything else —
# a child that is open, missing, in a repository the credential cannot read, a
# pull request unmerged, a check red or still pending, a manifest line that is
# not a URL, a tracker naming no child at all — leaves the tracker open and
# emits **one** finding saying which. It never guesses, and there is no state in
# which absence of evidence reads as delivery.
#
# ## What it never does
#
# It closes no child, merges no pull request, moves no card and edits no body.
# Closing the tracker moves its own card to Done by itself (`agents/board.md`),
# which is the only board effect it has.
set -uo pipefail

REPO=${GITHUB_REPOSITORY:-Kolonie-AI/kolonie-docs}
RUN_URL=${RUN_URL:-no run url}
LOOKBACK=${TRACKER_LOOKBACK:-100}

TRACKER_MARKER='<!-- package-tracker -->'

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

# One child, asked of GitHub: is the issue closed, and what closed it.
#
# `closedByPullRequestsReferences` rather than a search over branches: it is the
# relation GitHub itself maintains from `Closes #n`, so it answers *which pull
# request delivered this* rather than *which pull request mentions it*. The
# rollup is the same field a person reads as the tick beside a merge.
child_query='
query($owner:String!,$name:String!,$number:Int!){
  repository(owner:$owner,name:$name){
    issue(number:$number){
      state
      closedByPullRequestsReferences(first:20,includeClosedPrs:true){
        nodes{
          number
          merged
          url
          statusCheckRollup: commits(last:1){
            nodes{ commit{ statusCheckRollup{ state } } }
          }
        }
      }
    }
  }
}'

# The manifest lines of one body, as `<owner>/<repo> <number> <kind>`, and a
# `malformed` line for anything under the marker that is not a child URL. A
# manifest that cannot be read is a finding rather than an empty list — the
# distinction `board-self-check.sh` spends its floor argument on, one level down.
manifest_of() {
  jq -rn --arg body "$1" '
    $body
    | split("\n")[]
    | select(test("^<!-- tracker-child:"))
    | sub("^<!-- tracker-child:\\s*"; "") | sub("\\s*-->$"; "")
    | if test("^https://github\\.com/[^/]+/[^/]+/issues/[0-9]+( no-code)?$")
      then (capture("^https://github\\.com/(?<owner>[^/]+)/(?<name>[^/]+)/issues/(?<number>[0-9]+)(?<kind> no-code)?$")
            | "\(.owner)/\(.name)\t\(.number)\t\(if .kind == null or .kind == "" then "code" else "no-code" end)")
      else "malformed\t\(.)\tmalformed"
      end'
}

# The verdict on one child, as `<status>\t<row>`. `status` is `ok` or anything
# else; `row` is the table line a reader checks it by.
verify_child() {
  local slug=$1 number=$2 kind=$3
  local owner=${slug%%/*} name=${slug##*/} answer issue state prs merged url rollup

  if ! answer=$(gh api graphql -f query="$child_query" \
      -f owner="$owner" -f name="$name" -F number="$number" 2>/dev/null); then
    printf 'unreadable\t| `%s#%s` | — | — | the issue could not be read |\n' "$slug" "$number"
    return
  fi

  issue=$(jq -r '.data.repository.issue // empty' <<<"$answer" 2>/dev/null)
  if [ -z "$issue" ]; then
    printf 'missing\t| `%s#%s` | — | — | no such issue |\n' "$slug" "$number"
    return
  fi

  state=$(jq -r '.state // ""' <<<"$issue")
  if [ "$state" != CLOSED ]; then
    printf 'open\t| `%s#%s` | %s | — | still open |\n' "$slug" "$number" "${state:-unknown}"
    return
  fi

  if [ "$kind" = no-code ]; then
    printf 'ok\t| `%s#%s` | CLOSED | — | no-code child, no pull request required |\n' "$slug" "$number"
    return
  fi

  # The merged one, if there is one: a child may carry several references and
  # only the merged pull request delivered it.
  prs=$(jq -c '[.closedByPullRequestsReferences.nodes[]? | select(. != null)]' <<<"$issue")
  merged=$(jq -c 'map(select(.merged == true)) | first // empty' <<<"$prs")

  if [ -z "$merged" ]; then
    if [ "$(jq 'length' <<<"$prs")" -eq 0 ]; then
      printf 'no-pull-request\t| `%s#%s` | CLOSED | — | closed with no pull request |\n' "$slug" "$number"
    else
      url=$(jq -r 'first | .url' <<<"$prs")
      printf 'unmerged\t| `%s#%s` | CLOSED | %s | unmerged |\n' "$slug" "$number" "$url"
    fi
    return
  fi

  url=$(jq -r '.url' <<<"$merged")
  rollup=$(jq -r '.statusCheckRollup.nodes[0].commit.statusCheckRollup.state // ""' <<<"$merged")

  case "$rollup" in
    SUCCESS) printf 'ok\t| `%s#%s` | CLOSED | %s | SUCCESS |\n' "$slug" "$number" "$url" ;;
    '')      printf 'no-checks\t| `%s#%s` | CLOSED | %s | no check reported |\n' "$slug" "$number" "$url" ;;
    *)       printf 'checks\t| `%s#%s` | CLOSED | %s | %s |\n' "$slug" "$number" "$url" "$rollup" ;;
  esac
}

trackers=$(gh issue list --repo "$REPO" --state open --limit "$LOOKBACK" \
  --json number,body 2>/dev/null) || {
  echo "::error::the open issues could not be listed; no tracker was judged"
  exit 1
}

eligible=$(jq -c --arg marker "$TRACKER_MARKER" \
  '[.[] | select(.body != null and (.body | contains($marker)))]' <<<"${trackers:-[]}")

count=$(jq 'length' <<<"$eligible")
if [ "${count:-0}" -eq 0 ]; then
  echo "no open issue carries the package-tracker marker"
  exit 0
fi

held=0
for index in $(seq 0 $((count - 1))); do
  number=$(jq -r --argjson i "$index" '.[$i].number' <<<"$eligible")
  body=$(jq -r --argjson i "$index" '.[$i].body' <<<"$eligible")

  rows=()
  blockers=()
  children=0

  while IFS=$'\t' read -r slug child kind; do
    [ -n "${slug:-}" ] || continue
    children=$((children + 1))
    if [ "$slug" = malformed ]; then
      blockers+=("the manifest entry \`$child\` is malformed")
      rows+=("| \`$child\` | — | — | malformed manifest entry |")
      continue
    fi
    IFS=$'\t' read -r status row < <(verify_child "$slug" "$child" "$kind")
    rows+=("$row")
    [ "$status" = ok ] || blockers+=("\`$slug#$child\` is not verified delivered ($status)")
  done < <(manifest_of "$body")

  if [ "$children" -eq 0 ]; then
    blockers+=("this tracker carries the marker and lists no child")
  fi

  table=$(printf '%s\n' "| child | issue state | pull request | checks |" "| --- | --- | --- | --- |" \
    ${rows+"${rows[@]}"})

  if [ "${#blockers[@]}" -eq 0 ]; then
    comment=$(printf '%s\n\n%s\n\n%s\n' \
      "**Every manifested child is verified delivered**, so this tracker is closed. \`tracker-settle.sh\` closed it and nothing else: no child was closed, no pull request merged and no card moved by hand." \
      "$table" \
      "Closing the tracker moves its own card to Done. [Full run]($RUN_URL)")

    if $DRY_RUN; then
      echo "would close #$number"
      printf '%s\n' "$comment"
      continue
    fi

    # Comment first, close second: a tracker never ends without the evidence
    # that ended it being readable above the close.
    gh issue comment "$number" --repo "$REPO" --body "$comment" >/dev/null
    gh issue close "$number" --repo "$REPO" >/dev/null
    echo "closed #$number"
    printf '%s\n' "$comment"
    continue
  fi

  held=$((held + 1))
  comment=$(printf '%s\n\n%s\n\n%s\n\n%s\n' \
    "**This tracker stays open.** Its manifest was read and at least one child could not be verified delivered, so nothing was closed. A settlement pass never infers delivery from an absence of evidence." \
    "$table" \
    "$(printf -- '- %s\n' "${blockers[@]}")" \
    "[Full run]($RUN_URL)")

  if $DRY_RUN; then
    echo "would hold #$number open"
    printf '%s\n' "$comment"
    continue
  fi

  gh issue comment "$number" --repo "$REPO" --body "$comment" >/dev/null
  echo "held #$number open"
  printf '%s\n' "$comment"
done

$DRY_RUN && exit 0
[ "$held" -gt 0 ] && exit 1
exit 0
