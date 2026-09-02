#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def run(*args: str, capture: bool = False) -> str:
    result = subprocess.run(
        args, cwd=ROOT, text=True, stdout=subprocess.PIPE if capture else None, check=True
    )
    return result.stdout.strip() if result.stdout is not None else ""


def main() -> None:
    parser = argparse.ArgumentParser(description="Commit generated docs and open their follow-up PR")
    parser.add_argument("version")
    args = parser.parse_args()
    branch = f"docs-{args.version}"
    run("git", "config", "user.name", "github-actions[bot]")
    run("git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com")
    run("git", "switch", "--create", branch)
    run("git", "add", "www")
    if not run("git", "status", "--porcelain", capture=True):
        print("Generated documentation is already current.")
        return
    run("git", "commit", "--message", f"Add documentation for {args.version}")
    run("git", "push", "--force", "origin", branch)
    title = f"Add documentation for {args.version}"
    body = f"Adds the generated, versioned Weaver API documentation for release {args.version}."
    pr = run(
        "gh", "pr", "list", "--head", branch, "--state", "open", "--json", "number",
        "--jq", ".[0].number // empty", capture=True,
    )
    if pr:
        run("gh", "pr", "edit", pr, "--title", title, "--body", body)
    else:
        run("gh", "pr", "create", "--head", branch, "--title", title, "--body", body)


if __name__ == "__main__":
    main()
