#!/usr/bin/env python3
from __future__ import annotations

import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    for command in (
        ["roc", "fmt", "--check", "package", "examples"],
        ["roc", "check", "package/main.roc"],
        ["roc", "test", "package/main.roc"],
    ):
        subprocess.run(command, cwd=ROOT, check=True)


if __name__ == "__main__":
    main()
