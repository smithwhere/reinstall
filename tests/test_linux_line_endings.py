#!/usr/bin/env python3
"""Reject Windows line endings and BOMs in Linux installer files."""

from pathlib import Path
import sys


root = Path(__file__).resolve().parent.parent
paths = (
    [Path(name) for name in sys.argv[1:]]
    if len(sys.argv) > 1
    else sorted([*root.rglob("*.sh"), *root.rglob("*.cfg")])
)
if not paths:
    sys.exit("FAIL: no Linux installer files found")

errors = []
for path in paths:
    data = path.read_bytes()
    if b"\r" in data:
        errors.append(f"{path}: contains CR/CRLF; Linux installers require LF")
    if data.startswith(b"\xef\xbb\xbf"):
        errors.append(f"{path}: contains a UTF-8 BOM")
    if not data.endswith(b"\n"):
        errors.append(f"{path}: missing the final LF")

if errors:
    sys.exit("FAIL: " + "\n".join(errors))
print(f"PASS: {len(paths)} Linux installer files use LF without a BOM.")
