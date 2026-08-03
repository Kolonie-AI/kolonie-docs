# The Reviewer Agent is a GitHub Action, and it hangs off CI rather than off the pull request

[← the register](../decisions.md)

**Date:** 2026-08-01 — `kolonie-docs#42`

**The issue left this open and leaned the other way.** It offered a job on the
VPS or a GitHub Action, and preferred the VPS *"precisely because the PRs we care
about come from forks, where option 1 is weakest"* — an Action needing an API key
in CI, which a fork's pull request must not be able to reach.

**The premise is right and the conclusion does not follow.** `pull_request_target`
and `workflow_run` both run in the *base* repository's context, with secrets and a
writable token, for a pull request from a fork. What leaks a secret is checking
out the fork's code and running it; the trigger by itself does not. This
repository already relies on that distinction and says so: `inbound-triage.yml`
has been labelling fork pull requests since `#41`, under a comment explaining that
the job never checks anything out and that this is what makes the trigger safe.

So the fork case, which was the whole argument for the VPS, is not one. What is
left points the other way: no service to operate, no deploy chain, no second place
for the key to live, and a review that appears while the contributor is still
looking at the page rather than on the next poll.

**`workflow_run` on CI, not `pull_request_target` on the pull request**, and this
is the part worth keeping. `operations/review-guidelines.md` says *"CI must pass
before review begins"*, which is the rule in that document the **reviewer** can
enforce rather than request — not, as this said until 2026-08-01, the only
machine-enforceable rule in it. That document names two more (no force-push on
`main`, no secrets in code) and claims all of them are enforced; what is actually
configured is `kolonie-docs#96`. On `opened` there is no build yet, so a reviewer
would have to poll for one — and a reviewer that polls will eventually review
something it should not have. Hanging it off CI's completion means no code path
exists that runs before a build has a verdict. `synchronize` comes free, because
CI already runs on it.

**Two caps that are not the model's to argue with.** A red, cancelled or missing
build is never reviewed at all. A diff touching the ledger, the verifiers,
governance or erasure is forced to `COMMENT` however the model votes — the review
is still written and still specific, but a human decides. `kolonie-platform`'s
`AGENTS.md` §87 already states the reason: a process that could reward its own
results cannot gate itself, and the ledger is what pays.

**It runs as `github-actions[bot]`**, so the bot account `#42` listed as missing
turned out not to be needed. `GITHUB_TOKEN` can post a review with a verdict; what
it cannot do is review a pull request it opened itself, which is capped rather
than allowed to fail.

**What this costs, stated rather than discovered later.** The reviewer reads a
diff and nothing else. It cannot run a test, so any sentence it writes about a
test passing is a guess — the prompt forbids it and the posted review says so
outright, because the failure mode of a confident automated reviewer is a
maintainer who stops reading. It is also capped at 240 KB of diff, and a
truncation is disclosed in the review rather than absorbed.

**What would invalidate this.** A reviewer that needs to *run* the contributor's
code to say anything useful — a test executor rather than a reader. That cannot
live in a job holding a writable token, and it is the version of this that belongs
on the VPS after all.
