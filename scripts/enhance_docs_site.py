#!/usr/bin/env python3
"""Add the vendored Roc syntax highlighter to generated documentation."""

from __future__ import annotations

import argparse
import os
from pathlib import Path


def enhance_html(site: Path, html_file: Path) -> bool:
    document = html_file.read_text(encoding="utf-8")
    if "roc-highlight.js" in document and "roc-highlight.css" in document:
        return False
    script_path = os.path.relpath(site / "roc-highlight.js", html_file.parent).replace(os.sep, "/")
    style_path = os.path.relpath(site / "roc-highlight.css", html_file.parent).replace(os.sep, "/")
    if "</head>" not in document or "</body>" not in document:
        raise ValueError(f"cannot enhance {html_file}: incomplete HTML document")
    document = document.replace(
        "</head>", f'    <link rel="stylesheet" href="{style_path}">\n</head>', 1
    )
    document = document.replace(
        "</body>", f'    <script type="module" src="{script_path}"></script>\n</body>', 1
    )
    html_file.write_text(document, encoding="utf-8", newline="\n")
    return True


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("site", type=Path)
    args = parser.parse_args()
    site = args.site.resolve()
    for asset in ("roc-highlight.js", "roc-highlight.css"):
        if not (site / asset).is_file():
            raise SystemExit(f"Missing highlighter asset: {site / asset}")
    changed = sum(enhance_html(site, html_file) for html_file in (site / "main").rglob("*.html"))
    print(f"Added Roc syntax highlighting to {changed} API documentation pages")


if __name__ == "__main__":
    main()
