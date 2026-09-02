#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

try:
    from scripts.github_output import write_output
except ModuleNotFoundError:
    from github_output import write_output


ROOT = Path(__file__).resolve().parents[1]
NIGHTLY_RE = re.compile(r"nightly-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9a-f]{7}")


def main() -> None:
    version_file = ROOT / ".roc-version"
    nightly_tag = version_file.read_text(encoding="utf-8").strip()
    if NIGHTLY_RE.fullmatch(nightly_tag) is None:
        raise SystemExit(f"Invalid Roc nightly tag in {version_file}: {nightly_tag}")
    write_output("nightly-tag", nightly_tag)


if __name__ == "__main__":
    main()
