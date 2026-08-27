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


# ## The catalogue the gateway serves (`#502`)
#
# Measured 2026-08-26 against the configured gateway: `GET /v1/models` served the
# prefixed identifiers and neither bare name, and the bare names answered 503
# while the prefixed ones and the tier alias answered 200. This fixture is that
# measurement, with no address, key or response body in it — the served ids are
# the whole of what the loop needs to know.
SERVED = ("x-ai/grok-4.5", "openai/gpt-5.6-sol")

# What `served_models` is replaced with, per case: a tuple of served ids, or a
# reason it could not be read.
CATALOGUE: list = [SERVED, ""]

decide.served_models = lambda endpoint, key: (CATALOGUE[0], CATALOGUE[1])  # noqa: ARG005


def run(script: list[str], model: str | None = "openai/gpt-5.6-sol",
        fallback: str | None = None, credentials: bool = True,
        served: tuple = SERVED, catalogue_why: str = "") -> tuple:
    """Run one `ask()` against the script. Returns (answered, why, asked, slept, seconds)."""
    ASKED.clear()
    SLEPT.clear()
    CLOCK[0] = 1_000.0
    CATALOGUE[0], CATALOGUE[1] = served, catalogue_why
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
expect("one call when the first one answers", answered and asked == ["openai/gpt-5.6-sol"], why)
expect("and it does not wait for anything", slept == [], str(slept))

answered, why, asked, slept, _ = run(["fast", "answer"], fallback="x-ai/grok-4.5")
expect("a 502 is asked again, and the answer is used", answered, why)
expect("and the same model is asked, because it is the configured one",
       asked == ["openai/gpt-5.6-sol"] * 2, str(asked))
expect("after a pause, so a cooldown has a moment to clear",
       slept == [decide.RETRY_PAUSES[0]], str(slept))

answered, why, asked, slept, _ = run(["fast", "fast", "answer"], fallback="x-ai/grok-4.5")
expect("twice, with the longer pause second", answered and slept == list(decide.RETRY_PAUSES),
       str(slept))

answered, why, asked, slept, seconds = run(["fast"] * 3 + ["answer"], fallback="x-ai/grok-4.5")
expect("and then the other account, which is the point of the change",
       answered and asked == ["openai/gpt-5.6-sol"] * 3 + ["x-ai/grok-4.5"], str(asked))
expect("the whole of it inside a minute, well under the workflow's twenty",
       seconds < 60, f"{seconds:.0f}s")

answered, why, asked, slept, seconds = run(["fast"] * 6, fallback="x-ai/grok-4.5")
expect("nothing answering at all is three tries each and then a reason",
       not answered and asked == ["openai/gpt-5.6-sol"] * 3 + ["x-ai/grok-4.5"] * 3, str(asked))
expect("and that reason is the last status, not a guess",
       why == "the gateway answered 502", why)
expect("and it is still under a minute", seconds < 60, f"{seconds:.0f}s")


# ---------------------------------------------------------------------------
# And it does not, when asking again is only a slower way to fail.
# ---------------------------------------------------------------------------

print()
print("a failure where a second attempt is only more of the same")

answered, why, asked, slept, _ = run(["slow", "answer"], fallback="x-ai/grok-4.5")
expect("a slow failure skips its retries and hands over at once",
       answered and asked == ["openai/gpt-5.6-sol", "x-ai/grok-4.5"], str(asked))
expect("without waiting, because a hundred seconds was the wait", slept == [], str(slept))

answered, why, asked, slept, seconds = run(["slow", "slow"], fallback="x-ai/grok-4.5")
expect("two slow failures are two calls and no more",
       not answered and asked == ["openai/gpt-5.6-sol", "x-ai/grok-4.5"], str(asked))
# The expensive case, and the one the constants are chosen against: two hundred
# seconds is one Cloudflare cut per account and no retries at all. It is bounded
# rather than cheap — six such chunks would reach the workflow's twenty-minute
# timeout, which is the gateway being down rather than a chunk being unlucky.
expect("and two slow failures cost two cuts, not two cuts and four retries",
       seconds <= 2 * 110, f"{seconds:.0f}s")

answered, why, asked, slept, _ = run(["refused", "refused"], fallback="x-ai/grok-4.5")
expect("a 401 is never asked twice — a revoked key is not a rate limit",
       not answered and asked == ["openai/gpt-5.6-sol", "x-ai/grok-4.5"], str(asked))
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

expect("the default primary is a tier alias, which no vendor rename can retire",
       decide.DEFAULT_MODEL.startswith("@"), decide.DEFAULT_MODEL)
expect("and no second name is inferred, because inferring one is what #502 measured",
       decide.DEFAULT_FALLBACK_MODEL == "", repr(decide.DEFAULT_FALLBACK_MODEL))

answered, why, asked, _, _ = run(["fast"] * 3 + ["answer"], model="x-ai/grok-4.5",
                                 fallback="openai/gpt-5.6-sol")
expect("configured the other way round, the fallback is the other served name",
       answered and asked[-1] == "openai/gpt-5.6-sol", str(asked))

answered, why, asked, _, _ = run(["fast"] * 3, fallback="openai/gpt-5.6-sol", model="openai/gpt-5.6-sol")
expect("a fallback equal to the primary is not a second account, so it is not asked",
       not answered and asked == ["openai/gpt-5.6-sol"] * 3, str(asked))

answered, why, asked, _, _ = run(["fast"] * 3, fallback="none")
expect("and `none` switches the second account off entirely",
       not answered and asked == ["openai/gpt-5.6-sol"] * 3, str(asked))

# **The inference this replaces** (`#502`). An unset fallback used to become the
# other of two hard-coded bare names, and both had stopped being served — so the
# retry path could not reach a working model however often it ran. Unset now asks
# the configured model and stops.
answered, why, asked, _, _ = run(["fast"] * 3, fallback="")
expect("an unset fallback asks nobody else rather than inventing a second name",
       not answered and asked == ["openai/gpt-5.6-sol"] * 3, str(asked))

answered, why, asked, _, _ = run(["answer"], model="", served=decide.DEFAULT_MODEL and SERVED)
expect("and an empty model is the default tier alias",
       answered and asked == [decide.DEFAULT_MODEL], str(asked))

answered, why, asked, _, _ = run(["answer"], model=None)
expect("an unset model is the default, as it was before any of this",
       answered and asked == [decide.DEFAULT_MODEL], str(asked))

answered, why, asked, _, _ = run(["fast", "answer"], model="openai/gpt-5.6-sol",
                                 fallback="x-ai/grok-4.5")
expect("and both names are settings, so neither is spelt into the loop",
       answered and asked[0] == "openai/gpt-5.6-sol", str(asked))


# ---------------------------------------------------------------------------
# The catalogue: a model the gateway does not serve is never asked (#502).
#
# Measured 2026-08-26 through one healthy gateway: the two bare identifiers this
# file used to know answered 503 on every attempt, while the served prefixed
# names and the tier alias answered 200. A name that is absent from the
# catalogue fails identically every pass, so asking it on a schedule turns a
# configuration fault into a permanent quiet one.
# ---------------------------------------------------------------------------

print()
print("the model identifiers the gateway actually serves")

answered, why, asked, _, _ = run([], model="grok-4.5", fallback="gpt-5.6-sol")
expect("neither legacy bare identifier is asked at all",
       not answered and asked == [], str(asked))
expect("and the reason names the configuration rather than blaming the gateway",
       why.startswith("no configured model is served by the gateway"), why)

answered, why, asked, _, _ = run(["answer"], model="x-ai/grok-4.5")
expect("the served prefixed identifier is asked and answers",
       answered and asked == ["x-ai/grok-4.5"], str(asked))

answered, why, asked, _, _ = run(["answer"], model="@preset/tier-1")
expect("a tier alias is asked even though the catalogue does not list it",
       answered and asked == ["@preset/tier-1"], str(asked))

answered, why, asked, _, _ = run(["answer"], model="grok-4.5", fallback="openai/gpt-5.6-sol")
expect("an unserved primary is dropped and the served fallback still runs",
       answered and asked == ["openai/gpt-5.6-sol"], str(asked))

answered, why, asked, _, _ = run([], model="grok-4.5",
                                 served=(), catalogue_why="could not read the model catalogue: the gateway answered 404")
expect("an unreadable catalogue does not send a vendor-shaped name unverified",
       not answered and asked == [], str(asked))
expect("and says why nothing could be asked",
       why == "the model catalogue could not be read and no configured model is a tier alias", why)

answered, why, asked, _, _ = run(["answer"], model="@preset/tier-1",
                                 served=(), catalogue_why="could not read the model catalogue: the gateway answered 404")
expect("a tier alias remains askable when the catalogue cannot be read",
       answered and asked == ["@preset/tier-1"], str(asked))


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


# ---------------------------------------------------------------------------
# What the pass reports when it could not ask (#502).
#
# The measurement this is written against, 2026-08-26: three undecided issues,
# six 503s, `nothing was triaged this pass`, and a green run — forty-eight times
# a day while Inbox grew. `route()` still writes an empty decisions file on every
# ending, so one bad chunk costs its own issues and not the pass; the exit code
# is what tells the workflow which of the two endings happened.
# ---------------------------------------------------------------------------

print()
print("a pass that could not ask is not a pass that decided")

import json as _json  # noqa: E402 — the cases below need it and nothing above does
import tempfile  # noqa: E402


def route_with(script: list[str], brief: str, **kwargs) -> tuple:
    """Run `route()` over a brief. Returns (exit-code, decisions-written)."""
    ASKED.clear()
    CLOCK[0] = 1_000.0
    CATALOGUE[0] = kwargs.get("served", SERVED)
    CATALOGUE[1] = kwargs.get("catalogue_why", "")
    os.environ["TRIAGE_LLM_MODEL"] = kwargs.get("model", "openai/gpt-5.6-sol")
    os.environ.pop("TRIAGE_LLM_FALLBACK_MODEL", None)
    os.environ["TRIAGE_LLM_API_KEY"] = "not-a-key"
    os.environ["TRIAGE_LLM_BASE_URL"] = "https://gateway.invalid"
    decide.ask_once = gateway(script)

    with tempfile.TemporaryDirectory() as work:
        brief_path = os.path.join(work, "brief.md")
        out_path = os.path.join(work, "decisions.json")
        with open(brief_path, "w", encoding="utf-8") as fh:
            fh.write(brief)
        code = decide.route(brief_path, out_path)
        with open(out_path, encoding="utf-8") as fh:
            written = _json.load(fh)
    return code, written


CANDIDATES = "# The board\n\n## Kolonie-AI/kolonie-docs#500\n\nSomething undecided.\n"

# The reproduction: candidates existed, every attempt failed, nothing was routed.
code, written = route_with(["fast"] * 3, CANDIDATES)
expect("candidates and no answer exits non-zero, so the pass cannot report success",
       code == decide.NO_ANSWER, f"exit {code}")
expect("and it still writes an empty decisions file, so one chunk costs only its own issues",
       written == {"decisions": []}, str(written))

# The same ending by the route `#502` actually measured: names nobody serves.
code, written = route_with([], CANDIDATES, model="grok-4.5")
expect("an unserved model is the same ending — asked nothing, decided nothing, not green",
       code == decide.NO_ANSWER and ASKED == [], f"exit {code}, asked {ASKED}")

# A brief with nothing in it is the good case and must stay green — the workflow
# gates this step on `waiting != '0'`, so this is the belt to that brace.
code, written = route_with([], "# The board\n\nNothing is waiting.\n")
expect("no candidates exits 0 and asks no model at all",
       code == 0 and ASKED == [], f"exit {code}, asked {ASKED}")
expect("and writes the empty decisions file the merge step expects",
       written == {"decisions": []}, str(written))

# A model that answered and had nothing to change is a decided board, not a
# failure: the distinction the exit code exists to make.
code, written = route_with(["answer"], CANDIDATES)
expect("a model that answered with no decisions is green, because that is a quiet board",
       code == 0, f"exit {code}")

# And the retry path still completes normally, which is the tolerance `#502`
# explicitly keeps: one transient 5xx followed by a successful retry.
decide.ask_once = gateway(["fast", "answer"])
code, written = route_with(["fast", "answer"], CANDIDATES)
expect("one transient failure then an answer is an ordinary successful pass",
       code == 0, f"exit {code}")


print()
if FAILURES:
    print(f"{len(FAILURES)} failed: {', '.join(FAILURES)}")
    raise SystemExit(1)
print("all cases pass")
