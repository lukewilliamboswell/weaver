#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	roc: "nightly-2026-10-23-18478ff",
}

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import src/Script
import src/Svg

## Render the deploy example's source and its real terminal output as the
## README's SVG screenshot.
##
##     blueprint run capture
##
## Writes `assets/pretty-errors.svg`, or the file named by `OUTPUT`. The
## example is built with the `roc` on PATH, the compiler the package is
## tested with.
main! = |_args| {
	output = Path.utf8(Script.env_or!("OUTPUT", "assets/pretty-errors.svg")?)
	roc = Script.roc!()?
	source = match Svg.excerpt(Path.read_utf8!("examples/deploy.roc")?) {
		Ok(text) => text
		Err(MissingMarkers) => return Script.fail!("examples/deploy.roc: missing the # capture:start and # capture:end markers")
	}
	success_args = ["api:v2", "-e", "production", "-r", "4", "-l", "team=payments", "-n"]
	failure_args = ["api:v2", "--replicas", "4"]
	runs = Env.with_temp_dir!(
		|build| {
			executable = Path.join(build, "deploy")
			roc.run!(["build", "examples/deploy.roc", OsStr.from_str("--output=${Path.display(executable)}"), "--no-cache"])?
			success = run!(executable, success_args, 0)?
			failure = run!(executable, failure_args, 1)?
			Ok({ success, failure })
		},
	)?
	text = Str.join_with(
		[
			"\u(1b)[1;35mexamples/deploy.roc\u(1b)[0m",
			Svg.highlight(source),
			"",
			Svg.prompt("deploy ${Str.join_with(success_args, " ")}"),
			runs.success,
			"",
			Svg.prompt("deploy ${Str.join_with(failure_args, " ")}"),
			runs.failure,
		],
		"\n",
	)
	Path.write_utf8!(output, Svg.render(text))?
	Script.pass!("wrote ${Path.display(output)}")
}

# Run the example and return its standard output without trailing whitespace.
run! = |executable, args, expected| {
	output = Cmd.new(Path.to_os_str(executable))
		.args(args.map(OsStr.from_str))
		.stdout(Capture)
		.stderr(Capture)
		.run!()
		.map_err(|err| CommandRunFailed(Path.display(executable), err))?
	code = match output.status {
		Exited(value) => value
		Signaled(signal) => return Script.fail!("deploy was terminated by signal ${signal.to_str()}")
	}
	if code != expected {
		return Script.fail!("expected deploy ${Str.join_with(args, " ")} to exit with ${expected.to_str()}, got ${code.to_str()}: ${Str.from_utf8_lossy(output.stderr_bytes)}")
	}
	stdout = Str.from_utf8_lossy(output.stdout_bytes).trim_end()
	if stdout == "" {
		return Script.fail!("the deploy example printed nothing")
	}
	Ok(stdout)
}
