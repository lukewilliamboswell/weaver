#!/usr/bin/env python3
"""Build example programs and render their source and representative output as site pages."""

from __future__ import annotations

import argparse
import html
import json
import shlex
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DESCRIPTIONS = {
    "basic": "Required options, flags, optional parameters, and trailing values in one compact CLI.",
    "default-values": "Options and parameters with typed defaults and explicit overrides.",
    "deploy": "A realistic deployment command with validation, repeatable labels, and generated help.",
    "single-arg": "The smallest useful Weaver application: one required numeric option.",
    "subcommands": "Nested commands with options and parameters at multiple levels.",
}


def representative_case(app: dict[str, object]) -> dict[str, object]:
    cases = app["cases"]
    assert isinstance(cases, list)
    for case in cases:
        assert isinstance(case, dict)
        if case.get("exit_code", 0) == 0 and not case.get("unix_args_hex"):
            return case
    raise ValueError(f"{app['path']} has no successful representative case")


def render_page(name: str, description: str, source: str, command: str, output: str) -> str:
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="{html.escape(description, quote=True)}">
  <title>{html.escape(name)} example · Weaver</title>
  <link rel="stylesheet" href="../../vendor/simple-css/simple.min.css">
  <link rel="stylesheet" href="../../site.css">
  <link rel="stylesheet" href="../../roc-highlight.css">
</head>
<body>
  <header class="site-header">
    <a class="brand" href="../../">Weaver</a>
    <nav aria-label="Primary navigation"><a href="../../#examples">Examples</a><a href="../../main/">Latest docs</a><a href="https://github.com/lukewilliamboswell/weaver">GitHub</a></nav>
  </header>
  <main>
    <section class="example-hero">
      <p class="eyebrow">Example</p>
      <h1>{html.escape(name)}</h1>
      <p class="lede">{html.escape(description)}</p>
    </section>
    <section>
      <h2>In the terminal</h2>
      <div class="terminal-window">
        <div class="terminal-title" aria-hidden="true"><i></i><i></i><i></i></div>
        <pre><code><span class="prompt">$</span> {html.escape(command)}\n{html.escape(output.rstrip())}</code></pre>
      </div>
    </section>
    <section>
      <h2>Source</h2>
      <pre class="source"><code class="language-roc">{html.escape(source)}</code></pre>
      <p><a href="https://github.com/lukewilliamboswell/weaver/blob/main/examples/{html.escape(name)}.roc">View on GitHub →</a></p>
    </section>
  </main>
  <footer><p><a href="../../">Weaver</a> · command-line interfaces for Roc</p></footer>
  <script type="module" src="../../roc-highlight.js"></script>
</body>
</html>
"""


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("site", type=Path)
    parser.add_argument("--roc", default="roc")
    args = parser.parse_args()
    site = args.site.resolve()
    spec = json.loads((ROOT / "scripts" / "test_spec.json").read_text(encoding="utf-8"))
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
            command = shlex.join([f"./{name}", *case_args])
            page_dir = site / "examples" / name
            page_dir.mkdir(parents=True, exist_ok=True)
            page = render_page(
                name, DESCRIPTIONS.get(name, f"The {name} Weaver example."),
                source_path.read_text(encoding="utf-8"), command, result.stdout,
            )
            (page_dir / "index.html").write_text(page, encoding="utf-8", newline="\n")
            print(f"Generated example page for {name}")


if __name__ == "__main__":
    main()
