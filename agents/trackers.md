---
module: trackers
summary: Closing a package tracker on verified delivery, and how one registers its children.
applies-to:
  roles: [orchestrator]
  paths: [".github/scripts/tracker-settle.sh", ".github/workflows/tracker-settle.yml"]
---

# Closing a package tracker

Part of [`agents/board.md`](board.md) §4, routed here rather than carried into
every session: it is read by whoever writes a package, and by whoever changes the
pass that settles one.

## When a tracker may close itself

A tracker issue — the one that exists so a package has somewhere to be closed —
sits open after its last child lands, because nothing reads *the work is done*
off a set of other issues. `kolonie-platform#1754` sat in Blocked for two days
with all fourteen children closed and the last one merged green.

**`tracker-settle.sh` closes one, and only where the tracker asked it to.** Two
machine-readable lines in the body, and nothing else is read:

```
<!-- package-tracker -->
<!-- tracker-child: https://github.com/Kolonie-AI/kolonie-platform/issues/1755 -->
<!-- tracker-child: https://github.com/Kolonie-AI/kolonie-docs/issues/553 no-code -->
```

The marker makes the issue eligible. Each `tracker-child` line is one **binding**
child, named by URL so a child in another repository needs no convention about
which repository a bare number means. `no-code` says this child is a decision or
a close-out that no pull request delivers — written explicitly, because *this one
needed no code* is the judgement a pass must not make on somebody's behalf.

**It closes only on verified delivery.** Every listed child `CLOSED`, and every
child not marked `no-code` carrying a pull request that is merged with its checks
green. It posts the evidence as a table — child, issue state, pull request, check
conclusion — above the close.

**Anything it cannot establish leaves the tracker open with one finding saying
which**: a child still open, a child that does not exist, a repository the
credential cannot read, a pull request unmerged, a check red or still pending, a
manifest line that is not a child URL, or a marker with no child under it.

**Nothing is inferred.** The word *Epic*, a prose table and a checklist are all
read as prose, and an issue without the marker is not a tracker. Old trackers are
not retrofitted; a package that wants this adds the two lines.
