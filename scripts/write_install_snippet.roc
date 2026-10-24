#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	roc: "nightly-2026-10-23-18478ff",
}

import cli.Path
import src/Bundle
import src/Headers
import src/Published
import src/Release
import src/Script

## Write the parts of the manual that depend on what has been released: a
## first program holding the latest release's bundle URL, with links to its
## API reference, examples and notes; and the list of every version's API
## reference.
##
##     scripts/write_install_snippet.roc
##     RELEASE_VERSION=0.14.0 scripts/write_install_snippet.roc
##
## Writes `docs/generated/latest-release.adoc` and `api-versions.adoc`, which
## the manual includes and Git ignores. Needs `gh` to be authenticated. With
## `RELEASE_VERSION` the latest release is taken to be that one, with the
## bundle in `dist`, or the one `BUNDLE_PATH` names: the release workflow does
## this so a release's manual names that release.
main! = |_args| {
	generated : Path
	generated = "docs/generated"
	documented = Published.documented!()?
	# The first program runs on the platform the examples use.
	platform_url = match Headers.dependency(Path.read_utf8!("examples/single-arg.roc")?, "pf") {
		Ok(value) => value
		Err(_) => return Script.fail!("examples/single-arg.roc does not name its platform as pf")
	}
	(snippet, versions) = match Script.env_or!("RELEASE_VERSION", "")? {
		"" => {
			latest = Published.release!("")?
			bundle_file = match latest.assets.keep_if(Release.valid_bundle_file) {
				[only] => only
				_ => return Script.fail!("release ${latest.tag} does not have exactly one bundle attached")
			}
			examples = Release.find_examples_archive(latest.tag, latest.assets)
			(Release.install_snippet({ version: latest.tag, url: bundle_url!(latest.tag, bundle_file)?, platform_url, examples_asset: examples, documented: documented.contains(latest.tag) }), documented)
		}
		version => {
			bundle_file = Script.file_name(Bundle.selected!("dist")?)?
			# A prerelease publishes no API reference of its own.
			listed = if (Release.valid_docs_version(version) and !documented.contains(version)) documented.append(version) else documented
			(Release.install_snippet({ version, url: bundle_url!(version, bundle_file)?, platform_url, examples_asset: Zip(Release.examples_archive(version)), documented: listed.contains(version) }), listed)
		}
	}
	Path.create_all!(generated)?
	Path.write_utf8!(Path.join(generated, "latest-release.adoc"), snippet)?
	Path.write_utf8!(Path.join(generated, "api-versions.adoc"), Release.api_versions(versions))?
	Script.info!("GENERATED", Path.display(generated))
}

bundle_url! = |version, bundle_file|
	match Release.bundle_url(version, bundle_file) {
		Ok(url) => Ok(url)
		Err(_) => Script.fail!("${version} and ${bundle_file} do not name a release bundle")
	}
