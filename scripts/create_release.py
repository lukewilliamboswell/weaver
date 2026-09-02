#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import subprocess


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("release_tag", nargs="?", default=os.environ.get("RELEASE_TAG"))
    parser.add_argument("bundle_file", nargs="?", default=os.environ.get("BUNDLE_FILE"))
    args = parser.parse_args()
    if not args.release_tag or not args.bundle_file:
        parser.error("release tag and bundle file are required")
    roc_version = subprocess.run(
        ["roc", "version"], text=True, stdout=subprocess.PIPE, check=True
    ).stdout.strip()
    subprocess.run(
        [
            "gh", "release", "create", args.release_tag, args.bundle_file,
            "--title", args.release_tag, "--generate-notes",
            "--notes", f"Weaver package bundle built with Roc {roc_version}.",
        ],
        check=True,
    )


if __name__ == "__main__":
    main()
