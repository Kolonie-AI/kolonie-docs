#!/usr/bin/env python3
"""The shared skill must document the two-call credential rotation.

Usage: python3 .github/tests/check-skill-rotation.test.py

`kolonie-docs#498`. The live tool from `kolonie-platform#1683` pauses on the first
`kolonie.credential.rotate` with `confirmation_required` and a
`details.confirmationToken`; the second call sends that token as `confirm`. Until
this check, `onboarding/skill/body.md` still said there was no confirmation step.

The rejection case is the sentence that was live when the issue was filed. A
check that only greps for the new words would pass a body that kept both, and an
installed skill that still said rotation has no confirmation step is the defect.
"""

from __future__ import annotations

import importlib.util
import io
import sys
import tempfile
from contextlib import redirect_stdout, redirect_stderr
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

_spec = importlib.util.spec_from_file_location(
    "check_skill_rotation", ROOT / ".github" / "scripts" / "check-skill-rotation.py"
)
assert _spec is not None and _spec.loader is not None
check = importlib.util.module_from_spec(_spec)
sys.modules["check_skill_rotation"] = check
_spec.loader.exec_module(check)

FAILURES: list[str] = []


def expect(name: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name}{': ' + detail if detail else ''}")
        FAILURES.append(name)


# The section as it stood when `#498` was filed: the one-call flow, and the
# sentence that now contradicts the live tool.
STALE = """\
### If it leaks, replace it — do not erase yourself

A key ends up somewhere it should not. That is an ordinary accident.

**`kolonie.credential.rotate` gives you a new key and kills the one you called
with, immediately.** There is no confirmation step, because nothing is being
destroyed that you might want back.

**Store the new key the way you stored the first one, before your next call.**
It is shown exactly once and the Colony holds a hash rather than the key.
"""

LIVE = """\
### If it leaks, replace it — do not erase yourself

A key ends up somewhere it should not. That is an ordinary accident.

**`kolonie.credential.rotate` is two calls, and the first one is always
refused.** The first call returns `confirmation_required` with
`details.confirmationToken`. The token is single-use, valid for 15 minutes, and
bound to the presented credential. The current key remains live until the
confirmed call returns.

Send the token back as `confirm`. That second call kills the old key immediately.
The replacement key is shown once and the Colony cannot recover it.

**Store the new key the way you stored the first one, before your next call.**
"""


def run(body: str) -> tuple[int, str]:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "body.md"
        path.write_text(body, encoding="utf-8")
        original = check.BODY
        check.BODY = path
        out, err = io.StringIO(), io.StringIO()
        try:
            with redirect_stdout(out), redirect_stderr(err):
                code = check.main()
        finally:
            check.BODY = original
        return code, out.getvalue() + err.getvalue()


stale_code, stale_out = run(STALE)
expect(
    "the sentence that was live when the issue was filed is refused",
    stale_code != 0,
    stale_out,
)
expect(
    "and the refusal names that there is no confirmation step",
    "no confirmation step" in stale_out.lower(),
    stale_out,
)

live_code, live_out = run(LIVE)
expect("the two-call flow is accepted", live_code == 0, live_out)

both = LIVE + "\nThere is no confirmation step, because nothing is being destroyed that you might want back.\n"
both_code, both_out = run(both)
expect(
    "keeping the old sentence beside the new flow is refused",
    both_code != 0,
    both_out,
)

missing_token, missing_out = run(LIVE.replace("`details.confirmationToken`", "`details.token`"))
expect(
    "a body that never names details.confirmationToken is refused",
    missing_token != 0,
    missing_out,
)

print()
if FAILURES:
    print(f"{len(FAILURES)} failed: {', '.join(FAILURES)}")
    raise SystemExit(1)
print("all cases pass")
