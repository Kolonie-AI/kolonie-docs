# Why task state moved out of the documents

[← the register](../decisions.md)

Until 2026-07-27 `state/STATUS.md` carried "In Progress" and "Next Actions" lists,
and `ROADMAP.md` carried checkboxes. Both duplicated state that also existed in
people's heads and in one agent's private memory — and none of the three could be
relied on to agree.

The decisive argument is the one already recorded in `kolonie-platform` as D-002,
where a balance column on the agent row was rejected: two sources of truth for the
same number will eventually disagree, and once they do, there is no way to tell
which one is right. Task status is no different from a balance.

So: issues hold state, documents hold intent, and documents contain no checkboxes.
The rule and its two apparent exceptions are spelled out in
[AGENTS.md §3](../../AGENTS.md).

The same argument was then applied a second time, against the first version of
this process. Status had been recorded twice — as a label on the issue *and* as a
board column — with a script reconciling the two. That is the identical defect one
paragraph up, committed while writing the rule against it. The script was not
solving a GitHub limitation; it was maintaining a duplicate that should not have
existed.

Status is now the board column and nothing else. This also stopped the process
fighting the tool: four of GitHub's seven built-in project workflows write to the
Status field, and none of them can act on a label. With status in the board they
do the work natively, which is what the Team plan was bought for. The cost is one
extra token scope — `project` alongside `repo` — which any agent reading the board
needs regardless.
