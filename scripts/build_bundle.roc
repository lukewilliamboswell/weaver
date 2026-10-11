#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
}

import cli.OsStr
import cli.Path
import src/Files
import src/Script

main! = |_args| {
	# The bundle contains the package being developed, so it is built with the
	# floating nightly even though this script runs on roc-stable. OUTPUT_DIR
	# overrides the default dist/ directory.
	roc_nightly = Script.roc_nightly!()?
	output = Path.absolute!(Path.utf8(Script.env_str!("OUTPUT_DIR") ?? "dist"))?
	modules = Files.direct_roc_files!("package")?.map(Files.name)
	if !modules.contains("main.roc") {
		return Script.fail!("package/main.roc does not exist")
	}

	# Roc bundle takes the package root first, followed by each exposed module.
	bundle_args = ["bundle", "main.roc"]
		.concat(modules.keep_if(|filename| filename != "main.roc").map(OsStr.from_str))
		.concat(["--output-dir", Path.to_os_str(output)])

	Path.create_all!(output)?
	roc_nightly.cmd(bundle_args).cwd("package").exec_cmd!()
}
