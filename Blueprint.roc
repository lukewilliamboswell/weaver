app [config] { pf: platform "https://github.com/lukewilliamboswell/roc-blueprint/releases/download/0.4.0/4jmnCGtQeuXTJJYc1rPrnA1pQFPRqUecY5oau1te8cYn.tar.zst" }

config = [
	Name("weaver"),
	Overlay("roc", "github:roc-lang/roc-overlay"),
	Environment(
		"dev",
		[
			Overlays(["roc"]),
			Command("roc-stable", "rocpkgs.nightly-2026-10-09-258ab27"),
			Tools(["python3", "gh", "zip", "unzip"]),
		],
	),
	Shell("default", [Use("dev")]),
	Task("check", [Use("dev"), Run(["python3", "scripts/check_package.py"])]),
	Task("test", [Use("dev"), Run(["python3", "scripts/test.py"])]),
	Task("docs", [Use("dev"), Run(["python3", "scripts/serve_www.py"])]),
	Task("capture", [Use("dev"), Run(["python3", "scripts/capture_example.py"])]),
]
