#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
}

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import src/Capture
import src/Script

main! = |_args| {
	# Render the deploy example's source and its real terminal output as the
	# README's SVG. OUTPUT overrides the destination. The example is built with
	# the floating nightly.
	roc_nightly = Script.roc_nightly!()?
	output = Path.utf8(Script.env_str!("OUTPUT") ?? "assets/pretty-errors.svg")
	excerpt = Capture.source_excerpt(Path.read_utf8!("examples/deploy.roc")?)?

	terminal = Env.with_temp_dir!(
		|build_dir| {
			executable = Path.join(build_dir, "deploy")
			roc_nightly.run!(["build", "examples/deploy.roc", OsStr.from_str("--output=${Path.display(executable)}"), "--no-cache"])?
			success = run_example!(executable, ["api:v2", "-e", "production", "-r", "4", "-l", "team=payments", "-n"], 0)?
			failure = run_example!(executable, ["api:v2", "--replicas", "4"], 1)?
			Ok(
				Str.join_with(
					[
						"\u(1b)[1;35mexamples/deploy.roc\u(1b)[0m",
						excerpt,
						"",
						Capture.prompt("deploy api:v2 -e production -r 4 -l team=payments -n"),
						success,
						"",
						Capture.prompt("deploy api:v2 --replicas 4"),
						failure,
					],
					"\n",
				),
			)
		},
	)?
	Path.write_utf8!(output, Capture.svg(terminal))?
	Script.info!("CREATED", Path.display(output))
}

run_example! : Path, List(Str), I32 => Try(Str, _)
run_example! = |executable, args, expected_exit| {
	command = "deploy ${Str.join_with(args, " ")}"
	output = Cmd.new(Path.to_os_str(executable))
		.args(args.map(OsStr.from_str))
		.stdout(Capture)
		.stderr(Capture)
		.run!()
		.map_err(|err| ExampleRunFailed(command, Str.inspect(err)))?
	stdout = Str.trim_end(Str.from_utf8_lossy(output.stdout_bytes))
	match output.status {
		Exited(code) if code == expected_exit => {}
		other => return Script.fail!("expected ${command} to exit with ${expected_exit.to_str()}, got ${Str.inspect(other)}: ${Str.from_utf8_lossy(output.stderr_bytes)}")
	}
	if stdout == "" {
		return Script.fail!("${command} produced no stdout")
	}
	Ok(stdout)
}
