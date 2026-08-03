# Why the monorepo decision was reversed

[← the register](../decisions.md)

The 2026-07-23 multi-repo decision was made before any code existed. Reviewing it
on 2026-07-27, with three repos and two commits of code, three problems were clear
enough to reverse it while reversing was still nearly free:

1. **It worked against the Manifest.** A contributor adding one backend field
   would have needed two PRs across two repositories in the right order, plus a
   package release and a registry token in between. "Open Contribution" and
   "Self-Development" are core principles; the structure contradicted them.
2. **The orchestrator existed largely to manage the split.** Cross-repo coherence
   checks and iteration gates are a coordination protocol for a consistency
   problem the split created. In one workspace the typechecker does that job.
3. **The monorepo is the reversible choice.** `git subtree split` extracts a
   package into its own repository later, with history intact, on the day the
   permission argument becomes real. Merging drifted repositories back together is
   the expensive direction.

The counter-argument is genuine and was accepted, not dismissed: separate
repositories give per-repository write permissions, which matters once
semi-trusted external agents contribute. Until that day, CODEOWNERS and required
reviews cover it. When it arrives, split then.
