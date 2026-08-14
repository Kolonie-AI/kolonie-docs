---
module: history-chronicles
summary: decisions.md at 3052 lines and STATUS.md at 43 KB — how a reference stops being one.
applies-to:
---

# 2026-07-29 and 2026-08-03 — two reference files that became chronicles

`kolonie-docs#143`. The rules are in [`agents/docs-repo.md`](../docs-repo.md);
this is what produced them.

## state/decisions.md

**`state/decisions.md` then caught the same disease its parent died of**, and the
split above is the cure, taken on `kolonie-docs#143` on 2026-08-03. It was 3052
lines and had taken +3135/−82 in three weeks — it added more than its own size
and deleted 2.6 % of it. `STATUS.md` saw *more* traffic over the same window,
+1704/−1025, and stayed at 679 lines, because this file requires it to be present
tense and so it is rewritten rather than extended.

## state/STATUS.md, the same failure by annotation rather than by appending

Each one is cheap to write and permanent to read. A reader then has to work
through a refuted premise to reach the current fact, and every future edit has
more text to stay consistent with. The file grew from 11 KB to 43 KB in two days
this way, across 25 commits, not one of which made it smaller — until it broke the
session hook that loads this repository.


**The history is not lost, because Git has it.** What a bullet said yesterday is
one `git log -p` away, and that is the correct place for it.

## The third file, and the rule that came out of it later

`STATUS.md` was cured of *annotation* and went on growing anyway — 194 lines on
2026-07-29 to 919 on 2026-08-15, with deletions at 55 % of additions the whole
way. That is a different failure with the same symptom, and it is
[`state/decisions/status-md-grew-because-both-rules-bound-shape-and-neither-bound-count.md`](../../state/decisions/status-md-grew-because-both-rules-bound-shape-and-neither-bound-count.md).
