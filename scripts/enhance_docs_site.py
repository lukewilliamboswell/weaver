#!/usr/bin/env python3
"""Brand the generated API documentation and add the Roc syntax highlighter."""

from __future__ import annotations

import argparse
import os
from pathlib import Path


PACKAGE_NAME = "Weaver"
INTRO = """<section class="pkg-intro">
    <h2>{name} API documentation</h2>
    <p>{name} builds type-safe command-line interfaces in Roc. Compose options, parameters,
    and nested subcommands with builders, then let {name} handle parsing, validation,
    diagnostics, help, and version output.</p>
    <p>Pick a module from the sidebar, or search above. Start with
    <a href="Cli/">Cli</a> for assembling and running a parser,
    <a href="Opt/">Opt</a> and <a href="Param/">Param</a> for individual arguments, and
    <a href="SubCmd/">SubCmd</a> for nested commands.</p>
</section>
""".format(name=PACKAGE_NAME)
ASSETS = ("roc-highlight.js", "roc-highlight.css", "docs-extras.css")


def rebrand(site: Path, html_file: Path, document: str) -> str:
    """Replace Roc's directory-derived "package" name and link back to the site."""
    document = document.replace("<title>package Docs</title>", f"<title>{PACKAGE_NAME} Docs</title>", 1)
    home_path = os.path.relpath(site, html_file.parent).replace(os.sep, "/") + "/"
    marker = '<h1 class="pkg-full-name">'
    start = document.find(marker)
    if start == -1:
        raise ValueError(f"cannot rebrand {html_file}: no package heading")
    end = document.index("</h1>", start) + len("</h1>")
    heading = (
        f'{marker}<a href="{home_path}">{PACKAGE_NAME}</a></h1>'
        f'<p class="pkg-site-link"><a href="{home_path}">\u2190 Back to the {PACKAGE_NAME} site</a></p>'
    )
    document = document[:start] + heading + document[end:]
    if html_file.parent == site / "main":
        # Roc leaves the package landing page empty; give it an entry point.
        marker = '<div class="index-decoration">'
        if marker not in document:
            raise ValueError(f"cannot add an introduction to {html_file}")
        document = document.replace(marker, INTRO + marker, 1)
    return document


def enhance_html(site: Path, html_file: Path) -> bool:
    document = html_file.read_text(encoding="utf-8")
    if all(asset in document for asset in ASSETS):
        return False
    if "</head>" not in document or "</body>" not in document:
        raise ValueError(f"cannot enhance {html_file}: incomplete HTML document")
    def relative(asset: str) -> str:
        return os.path.relpath(site / asset, html_file.parent).replace(os.sep, "/")

    script_path = relative("roc-highlight.js")
    document = rebrand(site, html_file, document)
    styles = "".join(
        f'    <link rel="stylesheet" href="{relative(asset)}">\n'
        for asset in ("roc-highlight.css", "docs-extras.css")
    )
    document = document.replace("</head>", f"{styles}</head>", 1)
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
    for asset in ASSETS:
        if not (site / asset).is_file():
            raise SystemExit(f"Missing site asset: {site / asset}")
    changed = sum(enhance_html(site, html_file) for html_file in (site / "main").rglob("*.html"))
    print(f"Branded and highlighted {changed} API documentation pages")


if __name__ == "__main__":
    main()
