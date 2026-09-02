#!/usr/bin/env python3
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from github_output import write_output


ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    result = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "bundle.py"), "--output-dir", "dist"],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=True,
    )
    print(result.stdout, end="")
    match = re.search(r"^Created:\s+(.+\.tar\.zst)\s*$", result.stdout, re.MULTILINE)
    if match is None:
        raise SystemExit("Could not extract the bundle filename from roc bundle output")
    write_output("bundle_filename", Path(match.group(1)).name)


if __name__ == "__main__":
    main()
