#!/usr/bin/env python3
"""The Watch Agent's judgement half. `kolonie-docs#133`.

    watch-judge.py <dir>

Reads `<dir>/numbers.md`, asks the model whether the day is normal, and writes
`<dir>/judgement.json` and `<dir>/judgement.md`. Writes neither and exits 0 when
it cannot ask.

**Exiting 0 on every failure is the design, not laziness.** The deterministic
half of this agent — the silent-service check — has already run by the time this
starts, and `watch-agent.sh decide` treats a missing judgement as "no opinion"
rather than as "nothing is wrong". So a provider outage costs the day's
judgement and nothing else. The opposite arrangement, where this failing fails
the workflow, would turn every OpenRouter hiccup into a red run at 05:00 and
teach whoever reads it to stop looking.

That policy is `review-pull-request.yml`'s for a missing model key, and `#133` is
explicit that it applies to *half* of this agent and not to the whole of it.

**No threshold reaches the model either.** It is given yesterday and the seven
days before it and asked whether yesterday is unusual. Nothing in this file says
how many errors are too many, and nothing should.
"""
import json
import os
import sys
import urllib.error
import urllib.request

SYSTEM = """You are the Colony's Watch Agent. You are shown aggregated counts \
from one day of a small production system's logs, and the same counts for up to \
seven days before it. Decide whether the most recent day is abnormal.

**The history is as long as the store happens to hold, and it says how long that \
is.** Read that line before using the history at all. A single day of history is \
not a weekly baseline, and describing one bucket as a rate per day over a week is \
the specific error to avoid — it happened on this agent's first run. With little \
or no history, say that the comparison could not be made and set abnormal to \
false; do not manufacture a trend from one point.

You are not given log lines and you must not ask for any. Judge the numbers.

Abnormal means: a rate that has clearly departed from the preceding week, a new \
error slug that was not appearing before, or an error that is rare and severe on \
its face. It does not mean the presence of errors. A system with a steady handful \
of warnings a day is a working system, and saying so is the useful answer.

There is no threshold and you must not invent one for future runs. Judge this \
day against this history.

Answer as JSON: {"abnormal": true|false, "judgement": "one paragraph, plain \
prose, no bullet points"}. The paragraph names what you looked at and why you \
concluded what you did, so that a reader can disagree with you without re-running \
anything. If you are unsure, say so inside the paragraph and set abnormal to \
false — a person reads the numbers above your paragraph either way."""


def main() -> int:
    outdir = sys.argv[1]
    key = os.environ.get("OPENROUTER_API_KEY_WATCH", "")
    if not key:
        # Named as a configuration gap in the log, and nowhere else. `#133`: the
        # silent-service check must still run with no key, and the issue it opens
        # says the judgement was skipped — which `watch-agent.sh report` does by
        # finding no judgement.md.
        print("no OPENROUTER_API_KEY_WATCH — the numbers stand, no judgement was asked for",
              file=sys.stderr)
        return 0

    try:
        with open(os.path.join(outdir, "numbers.md"), encoding="utf-8") as fh:
            numbers = fh.read()
    except OSError as exc:
        print(f"could not read the numbers: {exc} — no judgement was written", file=sys.stderr)
        return 0

    body = json.dumps({
        "model": os.environ.get("MODEL", "deepseek/deepseek-v4-flash"),
        "messages": [{"role": "system", "content": SYSTEM},
                     {"role": "user", "content": numbers}],
        "response_format": {"type": "json_object"},
        # Small on purpose: the answer is a boolean and a paragraph. Large enough
        # that a model which thinks before answering does not run out mid-JSON,
        # which returns content: null and loses the whole answer rather than a
        # truncated one — measured in review-pull-request.yml, same lesson.
        "max_tokens": 2000,
        "temperature": 0.2,
    }).encode()

    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/chat/completions", data=body,
        headers={"Authorization": f"Bearer {key}",
                 "Content-Type": "application/json",
                 "HTTP-Referer": "https://github.com/Kolonie-AI",
                 "X-Title": "Kolonie Watch Agent"})
    try:
        answer = json.load(urllib.request.urlopen(req, timeout=120))
    except urllib.error.HTTPError as exc:
        # The status and nothing else. This log is public, and a provider's error
        # body can echo the request back with the key inside it.
        print(f"the model endpoint answered {exc.code} — no judgement was written", file=sys.stderr)
        return 0
    except Exception as exc:  # noqa: BLE001 — every way of not reaching it ends the same
        print(f"could not reach the model endpoint: {type(exc).__name__} — no judgement was written",
              file=sys.stderr)
        return 0

    choice = (answer.get("choices") or [{}])[0]
    text = (choice.get("message") or {}).get("content")
    if not text:
        print(f"the model returned no content (finish_reason: {choice.get('finish_reason') or 'unknown'})"
              " — no judgement was written", file=sys.stderr)
        return 0

    # A model asked for JSON usually returns JSON. "Usually" is not a contract.
    text = text.strip()
    if text.startswith("```"):
        text = text.strip("`")
        text = text.split("\n", 1)[1] if "\n" in text else text
    try:
        verdict = json.loads(text)
    except json.JSONDecodeError:
        print("the model did not return JSON — no judgement was written", file=sys.stderr)
        return 0

    paragraph = str(verdict.get("judgement") or "").strip()
    if not paragraph:
        print("the model returned no paragraph — no judgement was written", file=sys.stderr)
        return 0

    out = {"abnormal": bool(verdict.get("abnormal")), "judgement": paragraph}
    with open(os.path.join(outdir, "judgement.json"), "w", encoding="utf-8") as fh:
        json.dump(out, fh)
    with open(os.path.join(outdir, "judgement.md"), "w", encoding="utf-8") as fh:
        fh.write(paragraph + "\n")
    print(f"judgement written (abnormal: {out['abnormal']})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
