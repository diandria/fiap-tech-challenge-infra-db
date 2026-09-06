#!/usr/bin/env python3
"""
Rejects any ingress block open to the internet.

It exists because trivy does not cover this case. Verified empirically: with
`ingress { cidr_blocks = ["0.0.0.0/0"] }` on port 5432, trivy reports zero
findings at every severity while flagging the equivalent egress.

The `allowed_cidr_blocks` variable validation covers values passed by variable;
this check covers values written straight into the .tf.
"""
import re
import sys
from pathlib import Path

OPEN_CIDRS = ("0.0.0.0/0", "::/0")


def ingress_blocks(text: str):
    """Returns (start_line, body) for each ingress block, matching braces."""
    for match in re.finditer(r"\bingress\s*\{", text):
        start = match.end()
        depth = 1
        index = start
        while index < len(text) and depth:
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
            index += 1
        line = text.count("\n", 0, match.start()) + 1
        yield line, text[start : index - 1]


def main() -> int:
    findings = []
    for path in sorted(Path(".").rglob("*.tf")):
        if ".terraform" in path.parts:
            continue
        text = path.read_text()
        for line, body in ingress_blocks(text):
            for cidr in OPEN_CIDRS:
                if f'"{cidr}"' in body:
                    findings.append((path, line, cidr))

    if not findings:
        print("ok: no ingress open to the internet")
        return 0

    for path, line, cidr in findings:
        print(f"{path}:{line}: ingress open to {cidr}", file=sys.stderr)
    print(
        f"\n{len(findings)} open ingress block(s). "
        "Restrict the source before continuing.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
