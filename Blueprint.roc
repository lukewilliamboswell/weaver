# Development environment and tasks for weaver, realised by roc-blueprint without Nix.
#
#     blueprint run check    # everything the release workflow checks before packaging
#     blueprint run serve    # build the documentation site and preview it
#     blueprint shell        # the environment, to run scripts/*.roc directly
#     blueprint update       # refresh Blueprint.lock
#
# `roc-stable` runs repository scripts; `roc` on PATH tests the package and
# examples on the latest nightly, so nothing here provides a bare `roc`.
# Building, testing and publishing a release is the shared roc-automation
# workflow that .github/workflows/release.yml calls; it runs the `check`,
# `prepare-sbom`, `install-snippet` and `docs-path` tasks here.
# The released SBOM utility is a native executable. Blueprint embeds its
# configuration compiler independently of these environment inputs.
app [config] { pf: platform "https://github.com/lukewilliamboswell/roc-blueprint/releases/download/0.8.0/FbJymjYdCxx9vqMcau7r4tQfeAbnVGqqJoYrLGqPCqKu.tar.zst" }

import pf.Recipes
import pf.Config
import pf.System

docs_renderer : System -> Config.Download
docs_renderer = |system| match system {
	"x86_64-linux" | "aarch64-linux" | "aarch64-darwin" => File("https://github.com/lukewilliamboswell/roc-automation/releases/download/tools-0.4.0/roc-docs-${system.to_str()}")
	_ => Unavailable
}

sbom_binary : System -> Config.Download
sbom_binary = |system| match system {
	"x86_64-linux" | "aarch64-linux" | "aarch64-darwin" => File("https://github.com/lukewilliamboswell/roc-blueprint/releases/download/0.8.0/blueprint-sbom-${system.to_str()}")
	_ => Unavailable
}

config = [
	Name("weaver"),
	# The packages the bundle depends on, pinned by the SHA-256 their releases
	# publish so each supplier's SBOM can be bound to the exact file. They must
	# match the header of package/main.roc; scripts/check_all.roc checks that.
	SourceFile("roc-ansi", "https://github.com/lukewilliamboswell/roc-ansi/releases/download/0.13.3/BioPdu7WjVhTB2j1HaomKMi8htxsuwqwr79GbXY5nAUf.tar.zst", "93750a9b9993e4e2996feac0ddd6f199b6f3fd9ba81154a74f09f47481e1e2ba"),
	SourceFile("path", "https://github.com/roc-lang/path/releases/download/4.0.0/7YfABZPwJAXtLBY2vm8FqMyGAtNxncCJ65HdNKHFGNnE.tar.zst", "435499c7ffb4f357d2956e3bb2802a81264f6f2f50c896c9913fb86f7bc752bb"),
	Environment(
		"dev",
		[
			Programs([Fetch("roc-stable", Recipes.roc_nightly("nightly-2026-10-23-18478ff"))]),
			# Every bundle the scripts depend on, including dependencies of
			# dependencies: `roc-stable deps scripts/check_all.roc` lists them.
			RocPackages([
				"https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
				"https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
			]),
			# Programs the scripts start.
			Expect(["gh", "git", "gzip", "roc", "sh", "shasum", "tar", "unzip"]),
		],
	),
	Environment("docs", [Programs([Fetch("roc-docs", docs_renderer)]), Expect(["realpath", "sh"])]),
	Environment("sbom", [
		Extend("dev"),
		Programs([Fetch("blueprint-sbom", sbom_binary)]),
		Expect(["blueprint", "env", "git", "realpath", "roc", "sh", "shasum", "tar"]),
	]),
	Shell("default", [Use("dev")]),
	# Everything checked before the release workflow packages anything.
	Task("check", [Use("dev"), Run(["scripts/check_all.roc"])]),
	# The reviewed SBOM composition for the bundle the release workflow built.
	Task("prepare-sbom", [Use("dev"), Run(["scripts/prepare_sbom.roc"])]),
	Task("sbom-tool", [Use("sbom"), Run(["blueprint-sbom"])]),
	Task("docs", [Use("docs"), Run(["roc-docs", "build", "--workspace", ".", "--docs-directory", "docs", "--entrypoint", "index.adoc", "--pdf-filename", "weaver.pdf", "--site-url", "https://lukewilliamboswell.github.io/weaver/"])]),
	Task("docs-path", [Use("docs"), Run(["sh", "-c", "realpath \"$(command -v roc-docs)\""])]),
	# The parts of the manual that depend on what is released; see docs/contributing.adoc.
	Task("install-snippet", [Use("dev"), Run(["scripts/write_install_snippet.roc"])]),
	# The API reference of the GitHub Pages site: add it to the rendered manual,
	# or add it and preview the site locally.
	Task("site", [Use("dev"), Run(["scripts/build_site.roc"])]),
	Task("serve", [Use("dev"), Run(["scripts/serve_site.roc"])]),
	# Re-record assets/pretty-errors.svg from the deploy example's real output.
	Task("capture", [Use("dev"), Run(["scripts/capture_example.roc"])]),
]
