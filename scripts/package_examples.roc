#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
}

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import src/Files
import src/Script
import src/Text

main! = |_args| {
	# Build weaver-examples-<VERSION>.zip: complete copies of the examples whose
	# weaver dependency is BUNDLE_URL, the spec that describes their output, and
	# a short README. Nothing else in a header changes. Committed examples keep
	# the relative package path, so no release ever rewrites the repository.
	version = required!("VERSION")?
	bundle_url = required!("BUNDLE_URL")?
	repository = Script.env_str!("GITHUB_REPOSITORY") ?? "lukewilliamboswell/weaver"
	release_prefix = "https://github.com/${repository}/releases/download/${version}/"
	if !Text.valid_version(version) {
		return Script.fail!("VERSION is not a release version: ${version}")
	}
	if version == "0.0.0" or version.starts_with("0.0.0-") {
		# Roc reads 0.0.0 in a package URL as "no version" and rejects the URL.
		return Script.fail!("VERSION 0.0.0 is reserved by Roc; the lowest publishable version is 0.0.1")
	}
	if !bundle_url.starts_with(release_prefix) or !bundle_url.ends_with(".tar.zst") {
		return Script.fail!("BUNDLE_URL must be a .tar.zst under ${release_prefix}")
	}

	output = Path.absolute!(Path.utf8(Script.env_str!("OUTPUT_DIR") ?? "dist"))?
	Path.create_all!(output)?
	name = "weaver-examples-${version}"
	archive = Path.join(output, "${name}.zip")
	if Path.exists!(archive)? {
		Path.delete!(archive)?
	}

	Env.with_temp_dir!(
		|temporary| {
			root = Path.join(temporary, name)
			examples = Path.join(root, "examples")
			Path.create_all!(root)?
			Path.copy_dir!("examples", examples)?
			for source in Files.direct_roc_files!(examples)? {
				Path.write_utf8!(source, Text.rewrite_dependency(Path.read_utf8!(source)?, "weaver", bundle_url)?)?
			}
			Path.copy!("tests/spec.json", Path.join(root, "spec.json"))?
			Path.write_utf8!(Path.join(root, "README.md"), readme(version, repository, bundle_url))?
			Cmd.new("zip")
				.args(["-q", "-r", "-X", Path.to_os_str(archive), OsStr.from_str(name)])
				.cwd(temporary)
				.exec_cmd!()?
			Script.info!("CREATED", Path.display(archive))
		},
	)
}

required! : Str => Try(Str, _)
required! = |name|
	match Script.env_str!(OsStr.from_str(name)) {
		Ok(value) => Ok(value)
		Err(NotSet) => Script.fail!("${name} is required")
		Err(err) => Err(err)
	}

readme : Str, Str, Str -> Str
readme = |version, repository, bundle_url|
	Str.join_with(
		[
			"# Weaver ${version} examples",
			"",
			"These are the examples from https://github.com/${repository} as tested for",
			"release ${version}. Each one depends on that release's package bundle:",
			"",
			"    ${bundle_url}",
			"",
			"Run one with a current Roc nightly:",
			"",
			"    cd examples",
			"    roc basic.roc -- --help",
			"",
			"`spec.json` lists the arguments each example was tested with and the output",
			"it produced.",
			"",
		],
		"\n",
	)
