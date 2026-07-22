#!/usr/bin/env python3
"""Render the deploy example's source and real terminal output as an SVG."""

from __future__ import annotations

import argparse
import html
import os
import re
import subprocess
import tempfile
from dataclasses import dataclass, replace
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "assets" / "pretty-errors.svg"
EXAMPLE = ROOT / "examples" / "deploy.roc"
ROC = os.environ.get("ROC", "roc")
SGR_RE = re.compile(r"\x1b\[([0-9;]*)m")
ROC_TOKEN_RE = re.compile(r'("(?:[^"\\]|\\.)*"|#[^\n]*|\b[A-Z][A-Za-z0-9_.]*\b)')


@dataclass(frozen=True)
class Style:
    foreground: str = "#c9d1d9"
    bold: bool = False
    underline: bool = False


COLORS = {
    30: "#484f58",
    31: "#ff7b72",
    32: "#3fb950",
    33: "#d29922",
    34: "#58a6ff",
    35: "#bc8cff",
    36: "#39c5cf",
    37: "#c9d1d9",
    90: "#8b949e",
    91: "#ff7b72",
    92: "#56d364",
    93: "#e3b341",
    94: "#79c0ff",
    95: "#d2a8ff",
    96: "#56d4dd",
    97: "#f0f6fc",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"SVG destination (default: {DEFAULT_OUTPUT.relative_to(ROOT)})",
    )
    return parser.parse_args()


def source_excerpt() -> str:
    source = EXAMPLE.read_text(encoding="utf-8")
    start_marker = "# capture:start"
    end_marker = "# capture:end"
    if start_marker not in source or end_marker not in source:
        raise SystemExit(f"{EXAMPLE}: missing capture markers")

    excerpt = source.split(start_marker, 1)[1].split(end_marker, 1)[0].strip("\n")
    highlighted: list[str] = []
    for line_number, line in enumerate(excerpt.splitlines(), start=1):
        segments: list[str] = []
        cursor = 0
        for match in ROC_TOKEN_RE.finditer(line):
            segments.append(line[cursor : match.start()])
            token = match.group(0)
            color = 32 if token.startswith('"') else 36
            segments.append(f"\x1b[{color}m{token}\x1b[0m")
            cursor = match.end()
        segments.append(line[cursor:])
        code = "".join(segments).expandtabs(4)
        highlighted.append(f"\x1b[90m{line_number:>2} │\x1b[0m {code}")

    return "\n".join(highlighted)


def run_example(executable: Path, args: list[str], expected_exit: int) -> str:
    result = subprocess.run(
        [executable, *args],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != expected_exit:
        raise SystemExit(
            f"Expected deploy {' '.join(args)} to exit with {expected_exit}, "
            f"got {result.returncode}: {result.stderr!r}"
        )
    if not result.stdout:
        raise SystemExit(f"The deploy example produced no stdout. stderr: {result.stderr!r}")
    return result.stdout.rstrip()


def prompt(command: str) -> str:
    return f"\x1b[1;32m$\x1b[0m \x1b[1m{command}\x1b[0m"


def capture_example() -> str:
    temp_root = ROOT / ".weaver-tmp"
    temp_root.mkdir(exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="weaver-capture-", dir=temp_root) as temp_dir:
        executable = Path(temp_dir) / "deploy"
        subprocess.run(
            [ROC, "build", str(EXAMPLE.relative_to(ROOT)), f"--output={executable}", "--no-cache"],
            cwd=ROOT,
            check=True,
        )
        success_args = ["api:v2", "-e", "production", "-r", "4", "-l", "team=payments", "-n"]
        success = run_example(executable, success_args, 0)
        failure_args = ["api:v2", "--replicas", "4"]
        failure = run_example(executable, failure_args, 1)

    return "\n".join(
        [
            "\x1b[1;35mexamples/deploy.roc\x1b[0m",
            source_excerpt(),
            "",
            prompt("deploy api:v2 -e production -r 4 -l team=payments -n"),
            success,
            "",
            prompt("deploy api:v2 --replicas 4"),
            failure,
        ]
    )


def apply_sgr(style: Style, codes: list[int]) -> Style:
    if not codes:
        codes = [0]

    current = style
    for code in codes:
        if code == 0:
            current = Style()
        elif code == 1:
            current = replace(current, bold=True)
        elif code == 4:
            current = replace(current, underline=True)
        elif code == 22:
            current = replace(current, bold=False)
        elif code == 24:
            current = replace(current, underline=False)
        elif code == 39:
            current = replace(current, foreground=Style().foreground)
        elif code in COLORS:
            current = replace(current, foreground=COLORS[code])
    return current


def styled_runs(line: str) -> list[tuple[str, Style]]:
    runs: list[tuple[str, Style]] = []
    style = Style()
    cursor = 0

    for match in SGR_RE.finditer(line):
        if match.start() > cursor:
            runs.append((line[cursor : match.start()], style))
        raw_codes = match.group(1)
        codes = [int(code) for code in raw_codes.split(";") if code]
        style = apply_sgr(style, codes)
        cursor = match.end()

    if cursor < len(line):
        runs.append((line[cursor:], style))
    return runs


def render_svg(terminal_text: str) -> str:
    lines = terminal_text.splitlines()
    plain_lines = [SGR_RE.sub("", line) for line in lines]
    font_size = 14
    line_height = 22
    char_width = 8.45
    side_padding = 24
    title_height = 38
    content_padding = 20
    width = max(760, int(max(map(len, plain_lines), default=0) * char_width + side_padding * 2))
    height = title_height + content_padding * 2 + len(lines) * line_height

    rendered_lines: list[str] = []
    for index, line in enumerate(lines):
        spans: list[str] = []
        for text, style in styled_runs(line):
            attributes = [f'fill="{style.foreground}"']
            if style.bold:
                attributes.append('font-weight="700"')
            if style.underline:
                attributes.append('text-decoration="underline"')
            spans.append(f"<tspan {' '.join(attributes)}>{html.escape(text)}</tspan>")

        y = title_height + content_padding + font_size + index * line_height
        rendered_lines.append(
            f'<text x="{side_padding}" y="{y}" xml:space="preserve">{"".join(spans)}</text>'
        )

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title description">
  <title id="title">Weaver deployment CLI showcase</title>
  <desc id="description">Roc record-builder source followed by a successful typed deployment plan and a structured missing-option diagnostic.</desc>
  <rect width="{width}" height="{height}" rx="10" fill="#0d1117"/>
  <path d="M10 0h{width - 20}a10 10 0 0 1 10 10v28H0V10A10 10 0 0 1 10 0z" fill="#161b22"/>
  <circle cx="20" cy="19" r="5" fill="#ff7b72"/>
  <circle cx="38" cy="19" r="5" fill="#d29922"/>
  <circle cx="56" cy="19" r="5" fill="#3fb950"/>
  <text x="{width / 2}" y="24" text-anchor="middle" fill="#8b949e" font-family="ui-sans-serif, system-ui, sans-serif" font-size="12">Weaver · deploy showcase</text>
  <g font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, 'Liberation Mono', monospace" font-size="{font_size}">
    {chr(10).join(rendered_lines)}
  </g>
</svg>
"""


def main() -> None:
    args = parse_args()
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(render_svg(capture_example()), encoding="utf-8")
    print(f"Created {output.relative_to(ROOT) if output.is_relative_to(ROOT) else output}")


if __name__ == "__main__":
    main()
