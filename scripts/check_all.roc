#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
}

import cli.Env
import cli.OsStr
import cli.Path
import cli.Stderr
import src/Files
import src/Script
import src/StaticChecks

main! = |_args| {
	# Two compilers, two jobs. roc-stable is pinned by Blueprint.lock and runs
	# this repository's scripts, so tooling keeps working when a nightly breaks
	# something. The floating nightly checks the package and examples, because
	# that is the compiler users install today.
	roc_stable = Script.roc_stable!()?
	roc_nightly = Script.roc_nightly!()?

	Script.section!("COMPILERS")?
	roc_stable.run!(["version"])?
	roc_nightly.run!(["version"])?

	check_tooling!(roc_stable)?
	check_layout!()?
	check_package!(roc_nightly)?
	roc_stable.run!(["scripts/test_examples.roc"])
}

check_tooling! = |roc_stable| {
	Script.section!("TOOLING")?
	roc_stable.run!(["fmt", "--check", "scripts", "Blueprint.roc"])?
	roc_stable.run!(["test", "scripts/src/Text.roc"])?
	roc_stable.run!(["test", "scripts/src/StaticChecks.roc"])?
	for script in Files.direct_roc_files!("scripts")? {
		roc_stable.run!(["check", Path.to_os_str(script)])?
	}
	Ok({})
}

check_layout! = || {
	Script.section!("LAYOUT")?
	examples = read_sources!(Files.direct_roc_files!("examples")?)?
	sources = examples
		.concat(read_sources!(Files.all_roc_files!("package")?)?)
		.concat(read_sources!(Files.all_roc_files!("scripts")?)?)
		.concat(read_sources!(["Blueprint.roc"])?)
	problems = StaticChecks.pin_problems(Path.exists!(".roc-version")?, sources)
		.concat(StaticChecks.example_problems(examples))
	for problem in problems {
		Stderr.line!("error: ${problem}")?
	}
	if problems.is_empty() {
		Script.info!("PASS", "no compiler pins; every example uses the relative package path")
	} else {
		Err(LayoutProblems(problems.len()))
	}
}

read_sources! = |paths|
	paths.map_try!(|path| Ok({ path: Path.display(path), source: Path.read_utf8!(path)? }))

check_package! = |roc_nightly| {
	Script.section!("PACKAGE")?
	roc_nightly.run!(["fmt", "--check", "package", "examples"])?
	roc_nightly.run!(["check", "package/main.roc", "--no-cache"])?
	roc_nightly.run!(["test", "package/main.roc", "--no-cache"])?
	Env.with_temp_dir!(
		|output|
			roc_nightly.run!(["docs", "package/main.roc", OsStr.from_str("--output=${Path.display(output)}")]),
	)
}
