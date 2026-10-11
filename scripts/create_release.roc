#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
}

import cli.Cmd
import cli.OsStr
import cli.Path
import src/Files
import src/Script

main! = |_args| {
	# Publish RELEASE_TAG with the tested bundle and examples archive. The notes
	# state both compilers, which replaces a header pin as the record of what the
	# release was built and tested with.
	tag = required!("RELEASE_TAG")?
	bundle = required!("BUNDLE_FILE")?
	archive = required!("EXAMPLES_ARCHIVE")?
	for file in [bundle, archive] {
		if !Path.is_file!(Path.utf8(file))? {
			return Script.fail!("file does not exist: ${file}")
		}
	}

	nightly = version!(Script.roc_nightly!()?)?
	stable = version!(Script.roc_stable!()?)?
	notes = Str.join_with(
		[
			"Weaver package bundle built and tested with ${nightly}.",
			"",
			"Repository tooling ran on roc-stable: ${stable}.",
			"",
			"`${Files.name(Path.utf8(archive))}` holds the examples as tested against this bundle.",
		],
		"\n",
	)
	Script.command("gh").run!([
		"release",
		"create",
		OsStr.from_str(tag),
		OsStr.from_str(bundle),
		OsStr.from_str(archive),
		"--title",
		OsStr.from_str(tag),
		"--generate-notes",
		"--notes",
		OsStr.from_str(notes),
	])
}

required! : Str => Try(Str, _)
required! = |name|
	match Script.env_str!(OsStr.from_str(name)) {
		Ok(value) => Ok(value)
		Err(NotSet) => Script.fail!("${name} is required")
		Err(err) => Err(err)
	}

version! = |compiler| {
	output = compiler.cmd(["version"]).exec_output!().map_err(|err| VersionFailed(Str.inspect(err)))?
	Ok(Str.trim(output.stdout_utf8))
}
