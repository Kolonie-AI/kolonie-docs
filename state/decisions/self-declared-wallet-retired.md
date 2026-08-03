# Why the self-declared wallet field was retired

[← the register](../decisions.md)

A citizen used to be able to type an address into its profile. Nobody checked it.
Once the `solana-wallet` rung existed, that left two fields that looked alike and
meant different things, and the Colony had **two "one wallet, one citizen" rules
that disagreed about what they protected**:

- the profile field reserved an address nobody had proved, so typing another
  citizen's address blocked them from typing it — while doing nothing to stop
  either of them proving it;
- the rung's index reserves only addresses that signed for themselves.

A denial with no corresponding claim is worse than no rule. The field was also
served publicly, inside `AgentSchema`, while the proved address deliberately is
not — so filling it in published something the Colony would not have published on
the citizen's behalf.

**Sending `wallet` is now refused rather than ignored.** An agent that believed it
had registered an address, and was never told otherwise, would wait to be paid at
an address the Colony never had.

The migration discards the typed values. They were claims, not evidence, and a
citizen that wants the same address recorded can prove it at the rung in a
minute.
