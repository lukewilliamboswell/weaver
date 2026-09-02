#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from github_output import write_output


ROOT = Path(__file__).resolve().parents[1]
UPDATE_BRANCH = "update-roc-nightly"
NIGHTLY_RE = re.compile(r"nightly-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9a-f]{7}")


def run(*args: str, capture: bool = False) -> str:
    result = subprocess.run(
        args, cwd=ROOT, text=True, stdout=subprocess.PIPE if capture else None, check=True
    )
    return result.stdout.strip() if result.stdout is not None else ""


def resolve(requested_tag: str) -> None:
    nightly_tag = requested_tag or run(
        "gh", "release", "view", "--repo", "roc-lang/nightlies",
        "--json", "tagName", "--jq", ".tagName", capture=True,
    )
    if NIGHTLY_RE.fullmatch(nightly_tag) is None:
        raise SystemExit(f"Invalid Roc nightly tag: {nightly_tag}")
    write_output("nightly_tag", nightly_tag)


def bump(nightly_tag: str) -> None:
    version_file = ROOT / ".roc-version"
    if nightly_tag == version_file.read_text(encoding="utf-8").strip():
        print(f"Already pinned to {nightly_tag}; nothing to do.")
        write_output("changed", "false")
        return
    if NIGHTLY_RE.fullmatch(nightly_tag) is None:
        raise SystemExit(f"Invalid Roc nightly tag: {nightly_tag}")
    version_file.write_text(f"{nightly_tag}\n", encoding="utf-8", newline="\n")
    run("git", "config", "user.name", "github-actions[bot]")
    run("git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com")
    run("git", "switch", "--create", UPDATE_BRANCH)
    run("git", "add", ".roc-version")
    run("git", "commit", "--message", f"Update Roc nightly pin to {nightly_tag}")
    run("git", "push", "--force", "origin", UPDATE_BRANCH)
    write_output("changed", "true")


def pull_request(nightly_tag: str, test_result: str, run_url: str) -> None:
    if test_result == "success":
        status = ":white_check_mark: The complete Linux, macOS, and Windows test matrix passed."
    else:
        status = f":x: The test matrix finished with status `{test_result}`; this update needs attention before merging."
    title = f"Update Roc nightly pin to {nightly_tag}"
    body = (
        f"Updates `.roc-version` to [`{nightly_tag}`](https://github.com/roc-lang/nightlies/releases/tag/{nightly_tag}).\n\n"
        f"{status} See the [workflow run]({run_url}).\n\n"
        "This PR was created automatically by the `Update Roc nightly` workflow.\n"
    )
    pr = run(
        "gh", "pr", "list", "--head", UPDATE_BRANCH, "--state", "open",
        "--json", "number", "--jq", ".[0].number // empty", capture=True,
    )
    if pr:
        run("gh", "pr", "edit", pr, "--title", title, "--body", body)
    else:
        run("gh", "pr", "create", "--head", UPDATE_BRANCH, "--title", title, "--body", body)


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    resolve_parser = subparsers.add_parser("resolve")
    resolve_parser.add_argument("--requested-tag", default=os.environ.get("REQUESTED_TAG", ""))
    bump_parser = subparsers.add_parser("bump")
    bump_parser.add_argument("nightly_tag", nargs="?", default=os.environ.get("NIGHTLY_TAG"))
    pr_parser = subparsers.add_parser("pull-request")
    pr_parser.add_argument("nightly_tag", nargs="?", default=os.environ.get("NIGHTLY_TAG"))
    pr_parser.add_argument("test_result", nargs="?", default=os.environ.get("TEST_RESULT"))
    pr_parser.add_argument("run_url", nargs="?", default=os.environ.get("RUN_URL"))
    args = parser.parse_args()
    if args.command == "resolve":
        resolve(args.requested_tag)
    elif args.command == "bump":
        bump(args.nightly_tag)
    else:
        pull_request(args.nightly_tag, args.test_result, args.run_url)


if __name__ == "__main__":
    main()
