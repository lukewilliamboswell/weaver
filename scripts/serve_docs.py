#!/usr/bin/env python3
from __future__ import annotations

import argparse
import functools
import http.server
from pathlib import Path
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1]


class PagesRequestHandler(http.server.SimpleHTTPRequestHandler):
    repository_name = "weaver"

    def translate_path(self, path: str) -> str:
        request_path = urlsplit(path).path
        prefix = f"/{self.repository_name}"
        if request_path == prefix:
            path = "/"
        elif request_path.startswith(f"{prefix}/"):
            path = request_path[len(prefix) :]
        return super().translate_path(path)


def main() -> None:
    parser = argparse.ArgumentParser(description="Serve generated docs with GitHub Pages paths")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--docs-root", type=Path, default=ROOT / "www")
    parser.add_argument("--repository-name", default="weaver")
    args = parser.parse_args()

    docs_root = args.docs_root.resolve()
    if not (docs_root / "index.html").is_file():
        parser.error(f"{docs_root} is not a generated documentation site")

    handler = functools.partial(PagesRequestHandler, directory=str(docs_root))
    PagesRequestHandler.repository_name = args.repository_name.strip("/")
    with http.server.ThreadingHTTPServer((args.host, args.port), handler) as server:
        host, port = server.server_address[:2]
        print(f"Serving {docs_root} at http://{host}:{port}/{PagesRequestHandler.repository_name}/", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            print("\nStopped.")


if __name__ == "__main__":
    main()
