from __future__ import annotations

import os
from pathlib import Path


def write_output(name: str, value: str) -> None:
    output_path = os.environ.get("GITHUB_OUTPUT")
    if not output_path:
        raise SystemExit("GITHUB_OUTPUT is not set")
    with Path(output_path).open("a", encoding="utf-8", newline="\n") as output:
        output.write(f"{name}={value}\n")
