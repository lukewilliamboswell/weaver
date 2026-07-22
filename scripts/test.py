#!/usr/bin/env python3
from __future__ import annotations

import argparse
import difflib
import functools
import http.server
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC_PATH = ROOT / "scripts" / "test_spec.json"
LOCAL_PACKAGE_PATH = "../package/main.roc"
RELEASE_PACKAGE_PREFIX = "https://github.com/lukewilliamboswell/weaver/releases/download/"
PACKAGE_DEPENDENCY_RE = re.compile(r'(?m)^(?P<indent>\s*)weaver:\s*"(?P<dependency>[^"]+)",\s*$')
ROC = os.environ.get("ROC", "roc")
ANSI_SGR_RE = re.compile(r"\x1b\[[0-9;]*m")


def roc_path(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return path.resolve().as_posix()


def command(*args: str | Path, cwd: Path = ROOT) -> None:
    values = [str(arg) for arg in args]
    print(f"+ {' '.join(values)}", flush=True)
    subprocess.run(values, cwd=cwd, check=True)


def captured_command(*args: str | Path, cwd: Path = ROOT) -> subprocess.CompletedProcess[str]:
    values = [str(arg) for arg in args]
    print(f"+ {' '.join(values)}", flush=True)
    return subprocess.run(
        values,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=True,
    )


def load_spec() -> list[dict[str, object]]:
    data = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
    apps = data.get("apps")
    if not isinstance(apps, list) or not all(isinstance(app, dict) for app in apps):
        raise SystemExit(f"{SPEC_PATH}: 'apps' must be a list of objects")

    paths = [app.get("path") for app in apps]
    if not all(isinstance(path, str) for path in paths) or len(paths) != len(set(paths)):
        raise SystemExit(f"{SPEC_PATH}: every app needs a unique string path")

    discovered = {
        str(path.relative_to(ROOT).as_posix())
        for path in (ROOT / "examples").glob("*.roc")
    }
    specified = set(paths)
    if discovered != specified:
        raise SystemExit(
            f"Test spec mismatch; missing={sorted(discovered - specified)}, "
            f"extra={sorted(specified - discovered)}"
        )

    for app in apps:
        cases = app.get("cases")
        if not isinstance(cases, list) or not cases or not all(isinstance(case, dict) for case in cases):
            raise SystemExit(f"{app['path']}: cases must be a non-empty list of objects")
        names = [case.get("name") for case in cases]
        if not all(isinstance(name, str) and name for name in names) or len(names) != len(set(names)):
            raise SystemExit(f"{app['path']}: every case needs a unique non-empty name")
        for case in cases:
            validate_case(str(app["path"]), case)

    return apps


def validate_case(path: str, case: dict[str, object]) -> None:
    name = case["name"]
    args = case.get("args", [])
    if not isinstance(args, list) or not all(isinstance(arg, str) for arg in args):
        raise SystemExit(f"{path} [{name}]: args must be a list of strings")
    args_hex = case.get("unix_args_hex", [])
    if not isinstance(args_hex, list) or not all(isinstance(arg, str) for arg in args_hex):
        raise SystemExit(f"{path} [{name}]: unix_args_hex must be a list of hex strings")
    for value in args_hex:
        try:
            bytes.fromhex(value)
        except ValueError as error:
            raise SystemExit(f"{path} [{name}]: invalid hex argument {value!r}: {error}") from None
    exit_code = case.get("exit_code", 0)
    if not isinstance(exit_code, int):
        raise SystemExit(f"{path} [{name}]: exit_code must be an integer")
    timeout = case.get("timeout", 10)
    if not isinstance(timeout, (int, float)) or timeout <= 0:
        raise SystemExit(f"{path} [{name}]: timeout must be a positive number")

    assertion_keys = {
        "stdout",
        "stderr",
        "stdout_contains",
        "stderr_contains",
        "stdout_regex",
        "stderr_regex",
    }
    if not assertion_keys.intersection(case):
        raise SystemExit(f"{path} [{name}]: at least one output assertion is required")
    for stream in ("stdout", "stderr"):
        exact = case.get(stream)
        if exact is not None and not isinstance(exact, str):
            raise SystemExit(f"{path} [{name}]: {stream} must be a string")
        for suffix in ("contains", "regex"):
            values = case.get(f"{stream}_{suffix}", [])
            if not isinstance(values, list) or not all(isinstance(value, str) for value in values):
                raise SystemExit(f"{path} [{name}]: {stream}_{suffix} must be a list of strings")


def bundle_package(bundle_dir: Path) -> Path:
    result = captured_command(ROOT / "scripts" / "bundle.sh", "--output-dir", bundle_dir)
    print(result.stdout, end="")
    match = re.search(r"^Created:\s+(.+\.tar\.zst)\s*$", result.stdout, re.MULTILINE)
    if match is None:
        raise SystemExit("Could not find bundle path in roc bundle output")
    bundle = Path(match.group(1))
    if not bundle.is_file():
        raise SystemExit(f"Bundle was not created: {bundle}")
    return bundle.resolve()


class QuietRequestHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, _format: str, *_args: object) -> None:
        pass


class BundleServer:
    def __init__(self, bundle: Path) -> None:
        handler = functools.partial(QuietRequestHandler, directory=str(bundle.parent))
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.url = f"http://127.0.0.1:{self.server.server_port}/{bundle.name}"

    def __enter__(self) -> str:
        self.thread.start()
        return self.url

    def __exit__(self, *_args: object) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()


def uses_weaver_package(dependency: str) -> bool:
    return dependency == LOCAL_PACKAGE_PATH or (
        dependency.startswith(RELEASE_PACKAGE_PREFIX) and dependency.endswith(".tar.zst")
    )


def copy_examples_with_bundle_url(destination: Path, bundle_url: str) -> dict[str, Path]:
    target_dir = destination / "examples"
    shutil.copytree(ROOT / "examples", target_dir)
    rewritten: dict[str, Path] = {}

    for source in sorted(target_dir.glob("*.roc")):
        contents = source.read_text(encoding="utf-8")
        match = next(
            (
                candidate
                for candidate in PACKAGE_DEPENDENCY_RE.finditer(contents)
                if uses_weaver_package(candidate.group("dependency"))
            ),
            None,
        )
        if match is None:
            raise SystemExit(f"{source.name} does not use the expected Weaver package dependency")
        updated = (
            contents[: match.start()]
            + f'{match.group("indent")}weaver: "{bundle_url}",'
            + contents[match.end() :]
        )
        # Write bytes so Windows does not translate Roc's required LF endings
        # back to CRLF after replacing the package URL.
        encoded = updated.encode("utf-8")
        if b"\r\n" in encoded:
            raise SystemExit(f"{source.name}: rewritten Roc source contains CRLF line endings")
        source.write_bytes(encoded)
        rewritten[f"examples/{source.name}"] = source

    return rewritten


def validate_package(docs_dir: Path) -> None:
    print("\n=== PACKAGE ===")
    roc_sources = sorted((ROOT / "package").rglob("*.roc")) + sorted(
        (ROOT / "examples").rglob("*.roc")
    )
    for source in roc_sources:
        command(ROC, "fmt", "--check", roc_path(source))
    command(ROC, "check", "package/main.roc", "--no-cache")
    command(ROC, "test", "package/main.roc", "--no-cache")
    command(ROC, "docs", "package/main.roc", f"--output={roc_path(docs_dir)}")


def normalize_output(value: str) -> str:
    normalized_lines = value.replace("\r\n", "\n").replace("\r", "\n")
    return ANSI_SGR_RE.sub("", normalized_lines)


def assert_output(path: str, case: dict[str, object], stream: str, actual: str) -> None:
    name = str(case["name"])
    normalized = normalize_output(actual)
    raw_normalized = actual.replace("\r\n", "\n").replace("\r", "\n")
    raw_note = "" if raw_normalized == normalized else f"\n--- raw {stream} ---\n{raw_normalized!r}"
    if "[ROC CRASHED]" in normalized:
        raise SystemExit(f"{path} [{name}]: Roc runtime crash\n{normalized}{raw_note}")

    stream_assertions = {
        stream,
        f"{stream}_contains",
        f"{stream}_regex",
    }
    expected = case.get(stream)
    if stream == "stderr" and not stream_assertions.intersection(case):
        expected = ""
    if isinstance(expected, str):
        expected_normalized = normalize_output(expected)
        if normalized != expected_normalized:
            diff = "".join(
                difflib.unified_diff(
                    expected_normalized.splitlines(keepends=True),
                    normalized.splitlines(keepends=True),
                    fromfile=f"expected {stream}",
                    tofile=f"actual {stream}",
                )
            )
            raise SystemExit(f"{path} [{name}]: unexpected {stream}\n{diff}{raw_note}")

    for expected_text in case.get(f"{stream}_contains", []):
        if expected_text not in normalized:
            raise SystemExit(
                f"{path} [{name}]: missing {stream} output {expected_text!r}"
                f"\n--- {stream} ---\n{normalized}{raw_note}"
            )
    for pattern in case.get(f"{stream}_regex", []):
        if re.search(pattern, normalized, re.MULTILINE) is None:
            raise SystemExit(
                f"{path} [{name}]: {stream} did not match {pattern!r}"
                f"\n--- {stream} ---\n{normalized}{raw_note}"
            )


def case_enabled(case: dict[str, object]) -> bool:
    return not (os.name == "nt" and case.get("unix_args_hex"))


def run_case(path: str, binary: Path, case: dict[str, object]) -> None:
    name = str(case["name"])
    if not case_enabled(case):
        print(f"SKIP {path} [{name}]: raw Unix arguments are unavailable on Windows")
        return

    text_args = [str(value) for value in case.get("args", [])]
    raw_args = [bytes.fromhex(str(value)) for value in case.get("unix_args_hex", [])]
    if raw_args:
        args: list[str] | list[bytes] = [
            os.fsencode(binary),
            *(os.fsencode(value) for value in text_args),
            *raw_args,
        ]
    else:
        args = [str(binary), *text_args]

    print(f"CASE {path} [{name}]", flush=True)
    result = subprocess.run(
        args,
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=float(case.get("timeout", 10)),
    )
    stdout = result.stdout.decode("utf-8", errors="replace")
    stderr = result.stderr.decode("utf-8", errors="replace")
    expected_exit = int(case.get("exit_code", 0))
    if result.returncode != expected_exit:
        raise SystemExit(
            f"{path} [{name}]: exited with {result.returncode}, expected {expected_exit}"
            f"\n--- stdout ---\n{stdout}\n--- stderr ---\n{stderr}"
        )
    assert_output(path, case, "stdout", stdout)
    assert_output(path, case, "stderr", stderr)


def run_examples(apps: list[dict[str, object]], sources: dict[str, Path], build_dir: Path) -> None:
    print("\n=== EXAMPLES ===")
    build_dir.mkdir(parents=True, exist_ok=True)
    binaries: dict[str, Path] = {}
    suffix = ".exe" if os.name == "nt" else ""

    for app in apps:
        path = str(app["path"])
        source = sources[path]
        source_arg = roc_path(source)
        command(ROC, "fmt", "--check", source_arg)
        command(ROC, "check", source_arg, "--no-cache")
        command(ROC, "test", source_arg, "--no-cache")
        binary = build_dir / f"{source.stem}{suffix}"
        command(ROC, "build", source_arg, f"--output={roc_path(binary)}", "--no-cache")
        binaries[path] = binary

    print("\n=== SPEC CASES ===")
    total = 0
    skipped = 0
    for app in apps:
        path = str(app["path"])
        for case in app["cases"]:
            if case_enabled(case):
                total += 1
            else:
                skipped += 1
            run_case(path, binaries[path], case)
    print(f"\nAll {total} spec cases passed ({skipped} skipped).")


def local_sources() -> dict[str, Path]:
    return {
        f"examples/{source.name}": source
        for source in sorted((ROOT / "examples").glob("*.roc"))
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate Weaver and run bundled example specs")
    parser.add_argument("--bundle-path", type=Path, help="test an existing package bundle")
    parser.add_argument(
        "--examples-only",
        action="store_true",
        help="skip package validation when an earlier CI job already performed it",
    )
    args = parser.parse_args()

    if shutil.which(ROC) is None:
        raise SystemExit(f"{ROC!r} was not found on PATH")
    apps = load_spec()
    print(f"Using {subprocess.check_output([ROC, 'version'], text=True).strip()}")

    temp_parent = Path(os.environ.get("WEAVER_TMPDIR", ROOT / ".weaver-tmp"))
    temp_parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="weaver-test-", dir=temp_parent) as temporary:
        temp_dir = Path(temporary)
        if not args.examples_only:
            validate_package(temp_dir / "docs")

        if args.bundle_path is None and os.name == "nt":
            print("\nUsing local package source because package bundling is unavailable on Windows.")
            run_examples(apps, local_sources(), temp_dir / "build")
            return

        if args.bundle_path is None:
            bundle_dir = temp_dir / "bundle"
            bundle_dir.mkdir()
            bundle = bundle_package(bundle_dir)
        else:
            bundle = args.bundle_path.resolve()
            if not bundle.is_file():
                raise SystemExit(f"Bundle does not exist: {bundle}")

        with BundleServer(bundle) as bundle_url:
            print(f"Bundle: {bundle_url}")
            sources = copy_examples_with_bundle_url(temp_dir / "rewritten", bundle_url)
            run_examples(apps, sources, temp_dir / "build")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from None
    except subprocess.TimeoutExpired as error:
        raise SystemExit(f"Timed out after {error.timeout}s: {error.cmd}") from None
