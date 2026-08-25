#!/usr/bin/env python3
"""Does the router ask again when the gateway fails, and stop when it should not?

Usage: python3 .github/tests/board-triage-ask.test.py

`board-triage.test.sh` exercises everything the router does with an answer. This
file exercises what it does without one, which measurement on 2026-08-12 showed
is not rare: the gateway's `gpt-5.6-*` models are served by a single upstream
account, and when its short-window limit trips, `cli-proxy-api` has nothing to
rotate to and answers 502 or 503 within a second or two. Four of sixteen routing
chunks were lost that way in one morning — up to twenty-four issues left
undecided, silently, because a lost chunk looks exactly like a quiet board.

So `ask()` now retries and then asks the other account. The cases below are the
four decisions in that loop, and each is a way it could be wrong in a direction
nobody would notice:

* a **fast** failure is retried, because the cooldown clears inside a minute;
* a **slow** one is not, because Cloudflare cuts at about a hundred seconds and
  asking the same model again buys another hundred seconds of the same answer;
* a **4xx that is not a rate limit** is never retried, because a revoked key or
  a model name that no longer exists would become a slow fault instead of a
  loud one;
* and the fallback is the **other upstream account**, not a weaker model — the
  whole value is that it is a different account, and a small model routing the
  board unnoticed is the rule of thumb the script's docstring refuses.

`ask_once` is replaced throughout: this is a test of the loop's decisions, not of
HTTP. The clock is replaced too, so a case that describes a hundred-second
failure costs nothing to run.
"""

from __future__ import annotations

import importlib.util
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

_spec = importlib.util.spec_from_file_location(
    "board_triage_decide", ROOT / ".github" / "scripts" / "board-triage-decide.py"
)
assert _spec is not None and _spec.loader is not None
decide = importlib.util.module_from_spec(_spec)
sys.modules["board_triage_decide"] = decide
_spec.loader.exec_module(decide)


FAILURES: list[str] = []


def expect(name: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name}{': ' + detail if detail else ''}")
        FAILURES.append(name)


# ---------------------------------------------------------------------------
# The stand-ins: one clock nobody waits on, and one gateway that answers to a
# script. `decide.time` is the real time module, so patching it is patching it
# everywhere — which is why the clock is installed once, deliberately, and read
# through `CLOCK` rather than saved and restored per case.
# ---------------------------------------------------------------------------

CLOCK = [1_000.0]
SLEPT: list[float] = []
ASKED: list[str] = []

decide.time.monotonic = lambda: CLOCK[0]
decide.time.sleep = lambda seconds: (
    SLEPT.append(seconds), CLOCK.__setitem__(0, CLOCK[0] + seconds))

# What each scripted answer costs and what it returns, as `ask_once` returns it:
# (text, why-not, call, worth-asking-again).
ANSWERS = {
    # An answer, in the twenty seconds a real chunk takes.
    "answer": (20.0, ("{}", "", {"model": "", "tokens": 1}, False)),
    # The exhausted-account failure, at the speed it actually arrives.
    "fast": (2.0, ("", "the gateway answered 502", {"model": "", "tokens": None}, True)),
    # Cloudflare cutting the connection.
    "slow": (100.0, ("", "the gateway answered 524", {"model": "", "tokens": None}, True)),
    # A key that is no longer a key.
    "refused": (1.0, ("", "the gateway answered 401", {"model": "", "tokens": None}, False)),
}


def gateway(script: list[str]):
    """An `ask_once` that answers the script in order, recording who was asked."""
    remaining = list(script)

    def ask_once(endpoint, key, model, system, brief, budget):  # noqa: ANN001, ARG001
        ASKED.append(model)
        if not remaining:
            raise AssertionError(f"asked {model} more often than the case scripted")
        cost, result = ANSWERS[remaining.pop(0)]
        CLOCK[0] += cost
        return result

    return ask_once


def run(script: list[str], model: str | None = "gpt-5.6-sol",
        fallback: str | None = None, credentials: bool = True) -> tuple:
    """Run one `ask()` against the script. Returns (answered, why, asked, slept, seconds)."""
    ASKED.clear()
    SLEPT.clear()
    CLOCK[0] = 1_000.0
    for name, value in (("TRIAGE_LLM_MODEL", model),
                        ("TRIAGE_LLM_FALLBACK_MODEL", fallback)):
        os.environ.pop(name, None)
        if value is not None:
            os.environ[name] = value
    os.environ.pop("LLM_GATEWAY_API_KEY_TRIAGE", None)
    os.environ.pop("TRIAGE_LLM_API_KEY", None)
    if credentials:
        os.environ["TRIAGE_LLM_API_KEY"] = "not-a-key"
    os.environ["TRIAGE_LLM_BASE_URL"] = "https://gateway.invalid"

    decide.ask_once = gateway(script)
    text, why, _ = decide.ask("system", "brief", 100)
    return bool(text), why, list(ASKED), list(SLEPT), CLOCK[0] - 1_000.0


# ---------------------------------------------------------------------------
# It asks again when asking again is what would work.
# ---------------------------------------------------------------------------

print("a failure that a second attempt could answer differently")

answered, why, asked, slept, _ = run(["answer"])
expect("one call when the first one answers", answered and asked == ["gpt-5.6-sol"], why)
expect("and it does not wait for anything", slept == [], str(slept))

answered, why, asked, slept, _ = run(["fast", "answer"])
expect("a 502 is asked again, and the answer is used", answered, why)
expect("and the same model is asked, because it is the configured one",
       asked == ["gpt-5.6-sol"] * 2, str(asked))
expect("after a pause, so a cooldown has a moment to clear",
       slept == [decide.RETRY_PAUSES[0]], str(slept))

answered, why, asked, slept, _ = run(["fast", "fast", "answer"])
expect("twice, with the longer pause second", answered and slept == list(decide.RETRY_PAUSES),
       str(slept))

answered, why, asked, slept, seconds = run(["fast"] * 3 + ["answer"])
expect("and then the other account, which is the point of the change",
       answered and asked == ["gpt-5.6-sol"] * 3 + ["grok-4.5"], str(asked))
expect("the whole of it inside a minute, well under the workflow's twenty",
       seconds < 60, f"{seconds:.0f}s")

answered, why, asked, slept, seconds = run(["fast"] * 6)
expect("nothing answering at all is three tries each and then a reason",
       not answered and asked == ["gpt-5.6-sol"] * 3 + ["grok-4.5"] * 3, str(asked))
expect("and that reason is the last status, not a guess",
       why == "the gateway answered 502", why)
expect("and it is still under a minute", seconds < 60, f"{seconds:.0f}s")


# ---------------------------------------------------------------------------
# And it does not, when asking again is only a slower way to fail.
# ---------------------------------------------------------------------------

print()
print("a failure where a second attempt is only more of the same")

answered, why, asked, slept, _ = run(["slow", "answer"])
expect("a slow failure skips its retries and hands over at once",
       answered and asked == ["gpt-5.6-sol", "grok-4.5"], str(asked))
expect("without waiting, because a hundred seconds was the wait", slept == [], str(slept))

answered, why, asked, slept, seconds = run(["slow", "slow"])
expect("two slow failures are two calls and no more",
       not answered and asked == ["gpt-5.6-sol", "grok-4.5"], str(asked))
# The expensive case, and the one the constants are chosen against: two hundred
# seconds is one Cloudflare cut per account and no retries at all. It is bounded
# rather than cheap — six such chunks would reach the workflow's twenty-minute
# timeout, which is the gateway being down rather than a chunk being unlucky.
expect("and two slow failures cost two cuts, not two cuts and four retries",
       seconds <= 2 * 110, f"{seconds:.0f}s")

answered, why, asked, slept, _ = run(["refused", "refused"])
expect("a 401 is never asked twice — a revoked key is not a rate limit",
       not answered and asked == ["gpt-5.6-sol", "grok-4.5"], str(asked))
expect("and it says which status, so the run names a configuration fault",
       why == "the gateway answered 401", why)

answered, why, asked, _, _ = run([], credentials=False)
expect("no credentials asks nothing at all", not answered and asked == [], str(asked))
expect("and says so rather than blaming the gateway",
       why == "no gateway credentials — nothing was asked for", why)


# ---------------------------------------------------------------------------
# Which model is asked second, since that is the whole mechanism.
# ---------------------------------------------------------------------------

print()
print("the second account")

expect("the two names are different accounts upstream, which is why there are two",
       decide.DEFAULT_MODEL != decide.ACROSS_ACCOUNTS,
       f"{decide.DEFAULT_MODEL} / {decide.ACROSS_ACCOUNTS}")

answered, why, asked, _, _ = run(["fast"] * 3 + ["answer"], model="grok-4.5")
expect("configured the other way round, the fallback is the default model",
       answered and asked[-1] == decide.DEFAULT_MODEL, str(asked))

answered, why, asked, _, _ = run(["fast"] * 3, fallback="gpt-5.6-sol")
expect("a fallback equal to the primary is not a second account, so it is not asked",
       not answered and asked == ["gpt-5.6-sol"] * 3, str(asked))

answered, why, asked, _, _ = run(["fast"] * 3, fallback="none")
expect("and `none` switches the second account off entirely",
       not answered and asked == ["gpt-5.6-sol"] * 3, str(asked))

# The trap this guards: a workflow writing `${{ vars.TRIAGE_LLM_FALLBACK_MODEL }}`
# hands the script an empty string whenever nobody has set the variable. If empty
# meant *off*, wiring the setting up at all would quietly undo the change.
answered, why, asked, _, _ = run(["fast"] * 3 + ["answer"], fallback="")
expect("an empty setting is nobody having set it, not somebody switching it off",
       answered and asked[-1] == "grok-4.5", str(asked))

answered, why, asked, _, _ = run(["answer"], model="")
expect("and an empty model is the default for the same reason",
       answered and asked == [decide.DEFAULT_MODEL], str(asked))

answered, why, asked, _, _ = run(["answer"], model=None)
expect("an unset model is the default, as it was before any of this",
       answered and asked == [decide.DEFAULT_MODEL], str(asked))

answered, why, asked, _, _ = run(["fast", "answer"], model="whatever-is-configured",
                                 fallback="something-else")
expect("and both names are settings, so neither is spelt into the loop",
       answered and asked[0] == "whatever-is-configured", str(asked))


# ---------------------------------------------------------------------------
# The two callers, which take three values and must keep taking three.
# ---------------------------------------------------------------------------

print()
print("what the callers get")

run(["answer", "answer"])  # leaves one answer on the script, and the environment set
shape = decide.ask("system", "brief", 100)
expect("ask() still returns exactly (text, why, call), which is what route() unpacks",
       len(shape) == 3, str(len(shape)))
expect("and the third is the call `read_model_call` shape, for the run summary",
       isinstance(shape[2], dict) and set(shape[2]) == {"model", "tokens"}, str(shape[2]))


print()
if FAILURES:
    print(f"{len(FAILURES)} failed: {', '.join(FAILURES)}")
    raise SystemExit(1)
print("all cases pass")
