#!/usr/bin/env python3
"""Generate and locally preview the complete GitHub Pages site."""

from __future__ import annotations

import argparse
import functools
import http.server
import os
import sys
import webbrowser
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_docs_site import ROOT, assemble, require_pinned_roc, roc_executable


DEFAULT_OUTPUT = ROOT / "target" / "www-preview"


class PreviewHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format: str, *args: object) -> None:
        print(f"HTTP: {format % args}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--roc", default=os.environ.get("ROC", "roc"))
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=0, help="port to use; defaults to an available random port")
    parser.add_argument("--no-open", action="store_true")
    parser.add_argument("--no-serve", action="store_true")
    args = parser.parse_args()
    if not 0 <= args.port <= 65535:
        parser.error("--port must be between 0 and 65535")

    roc = roc_executable(args.roc)
    require_pinned_roc(roc)
    output = args.output.resolve()
    assemble(output, roc, "/main")
    if args.no_serve:
        return

    handler = functools.partial(PreviewHandler, directory=str(output))
    try:
        server = http.server.ThreadingHTTPServer((args.host, args.port), handler)
    except OSError as error:
        raise SystemExit(f"Could not listen on {args.host}:{args.port}: {error}") from None
    server.daemon_threads = True
    host, port = server.server_address[:2]
    display_host = "127.0.0.1" if host in {"0.0.0.0", "::"} else host
    if ":" in display_host:
        display_host = f"[{display_host}]"
    url = f"http://{display_host}:{port}/"
    print(f"Serving {output} at {url}", flush=True)
    if not args.no_open and not webbrowser.open(url):
        print("Could not open a browser automatically; open the URL above.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
