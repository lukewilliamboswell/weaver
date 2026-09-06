#!/usr/bin/env python3
"""Build and run each example, then show its terminal output on the landing page."""

from __future__ import annotations

import argparse
import html
import json
import shlex
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_URL = "https://github.com/lukewilliamboswell/weaver/blob/main/examples"
PLACEHOLDER = "<!--EXAMPLES-->"
TITLES = {
    "basic": "Basic",
    "default-values": "Default values",
    "deploy": "Deploy",
    "single-arg": "Single argument",
    "subcommands": "Subcommands",
}


def representative_case(app: dict[str, object]) -> dict[str, object]:
    cases = app["cases"]
    assert isinstance(cases, list)
    for case in cases:
        assert isinstance(case, dict)
        if case.get("exit_code", 0) == 0 and not case.get("unix_args_hex"):
            return case
    raise ValueError(f"{app['path']} has no successful representative case")


def render_card(name: str, command: str, output: str) -> str:
    title = html.escape(TITLES.get(name, name))
    body = f'<span class="prompt">$</span> {html.escape(command)}\n{html.escape(output.rstrip())}'
    return (
        f'<a class="example" href="{SOURCE_URL}/{name}.roc">'
        f'<span class="example-name">{title}<span class="example-file">{name}.roc</span></span>'
        f'<span class="terminal-window">'
        f'<span class="terminal-title" aria-hidden="true"><i></i><i></i><i></i></span>'
        f"<pre><code>{body}</code></pre>"
        f"</span></a>"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("site", type=Path)
    parser.add_argument("--roc", default="roc")
    args = parser.parse_args()
    site = args.site.resolve()
    spec = json.loads((ROOT / "scripts" / "test_spec.json").read_text(encoding="utf-8"))

    cards: list[str] = []
    with tempfile.TemporaryDirectory(prefix="weaver-doc-examples-") as temporary:
        build_dir = Path(temporary)
        for app in spec["apps"]:
            source_path = ROOT / app["path"]
            name = source_path.stem
            executable = build_dir / name
            subprocess.run(
                [args.roc, "build", str(source_path), f"--output={executable}", "--no-cache"],
                cwd=ROOT,
                check=True,
            )
            case = representative_case(app)
            case_args = case.get("args", [])
            result = subprocess.run(
                [str(executable), *case_args], cwd=ROOT, text=True,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True,
            )
            cards.append(render_card(name, shlex.join([f"./{name}", *case_args]), result.stdout))
            print(f"Captured terminal output for {name}")

    index = site / "index.html"
    document = index.read_text(encoding="utf-8")
    if PLACEHOLDER not in document:
        raise SystemExit(f"{index} is missing {PLACEHOLDER}")
    grid = '<div class="example-grid">' + "".join(cards) + "</div>"
    index.write_text(document.replace(PLACEHOLDER, grid, 1), encoding="utf-8", newline="\n")
    print(f"Added {len(cards)} examples to the landing page")


if __name__ == "__main__":
    main()
