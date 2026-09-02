#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser(description="Bundle the Weaver Roc package")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "dist")
    args, roc_args = parser.parse_known_args()

    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    package_dir = ROOT / "package"
    roc_files = ["main.roc", *(path.name for path in sorted(package_dir.glob("*.roc")) if path.name != "main.roc")]
    subprocess.run(
        [os.environ.get("ROC", "roc"), "bundle", *roc_files, "--output-dir", str(output_dir), *roc_args],
        cwd=package_dir,
        check=True,
    )


if __name__ == "__main__":
    main()
