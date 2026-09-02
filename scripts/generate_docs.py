#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VERSION_RE = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+")


def normalize_version(value: str) -> str:
    version = value.removeprefix("v")
    if VERSION_RE.fullmatch(version) is None:
        raise ValueError("version must use the x.y.z format")
    return version


def redirect_page(repository_name: str, version: str) -> str:
    url = f"/{repository_name}/{version}/"
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="0; url={url}">
  <link rel="canonical" href="{url}">
  <title>Redirecting to {version}</title>
</head>
<body>
  <p><a href="{url}">Redirecting to {version}</a></p>
</body>
</html>
"""


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate versioned Weaver documentation")
    parser.add_argument("version", nargs="?", default=os.environ.get("DOCS_VERSION"))
    parser.add_argument("--repository-name", default=os.environ.get("GITHUB_REPOSITORY", "/weaver").split("/")[-1])
    parser.add_argument("--docs-root", type=Path, default=Path("www"))
    args = parser.parse_args()
    if args.version is None:
        parser.error("VERSION is required (or set DOCS_VERSION)")
    try:
        version = normalize_version(args.version)
    except ValueError as error:
        parser.error(str(error))

    docs_root = args.docs_root if args.docs_root.is_absolute() else ROOT / args.docs_root
    output_dir = docs_root.resolve() / version
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [os.environ.get("ROC", "roc"), "docs", "package/main.roc", f"--output={output_dir}"],
        cwd=ROOT,
        check=True,
    )

    absolute_asset = re.compile(r'(href|src)="/')
    replacement = rf'\1="/{args.repository_name}/{version}/'
    for html_file in output_dir.rglob("*.html"):
        contents = html_file.read_text(encoding="utf-8")
        html_file.write_text(absolute_asset.sub(replacement, contents), encoding="utf-8", newline="\n")
    (output_dir.parent / "index.html").write_text(
        redirect_page(args.repository_name, version), encoding="utf-8", newline="\n"
    )
    print(f"Generated docs for {version} in {output_dir}")


if __name__ == "__main__":
    main()
