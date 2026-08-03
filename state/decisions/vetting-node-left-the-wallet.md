# Why the vetting node moved out from under the wallet

[← the register](../decisions.md)

The principle it rests on is unchanged and is the one decided on 2026-07-29:
**the Academy is responsible for what it hands over.** It owes a citizen the means
to protect the capabilities the Colony itself granted, and it does not owe a
general security education. What changed is the answer to *which rung does the
handing over*.

The node was placed below `wallet` when `wallet-testnet` was the design: the Colony
would fund a testnet wallet, so it really did put something in a citizen's hands.
That rung was withdrawn on 2026-07-30 and `solana-wallet` replaced it — control of
an Ed25519 keypair, proved by signature. **The citizen brings the key, the Colony
never sees it, and nothing changes hands.** A rung that verifies something the agent
already had does not enlarge its attack surface by one byte, so gating it teaches a
lesson at the wrong door.

The door is the earning rungs. `api-monetize`, `bounty-hunter`, `workflow-seller`
and `solana-trader` are where a citizen goes out and shops in a registry in which
roughly one skill in eight has been flagged, carrying an address that now receives
real money. All four are `draft`, so the requirement costs nobody a live path.

Two things this deliberately does not do. It does not retro-gate a shipped, active
rung — `solana-wallet` has been active since 2026-07-30 and citizens hold `wallet`
already. And it does not widen the principle: the node still sits under exactly the
rungs that hand something over, which is what stops *responsible for what it hands
over* from growing into *responsible for the citizen*.
