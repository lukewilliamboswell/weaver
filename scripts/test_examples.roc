#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
}

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stdout
import cli.Tcp
import src/Files
import src/Script
import src/Text

Case : {
	name : Str,
	args : Try(List(Str), [Missing]),
	unix_args_hex : Try(List(Str), [Missing]),
	exit_code : Try(I32, [Missing]),
	stdout : Try(Str, [Missing]),
	stdout_contains : Try(List(Str), [Missing]),
}

App : { path : Str, cases : List(Case) }

main! = |_args| {
	# Build every example against a package bundle and run the spec cases
	# against the binaries. Everything that touches the package uses ROC_NIGHTLY.
	#
	# By default the working tree's examples are tested against a bundle built
	# from the working tree. BUNDLE_PATH names an existing bundle to test instead.
	# EXAMPLES_ARCHIVE_DIR names an unpacked examples archive, which is tested
	# unchanged with its own spec: against BUNDLE_PATH when that is set, and
	# otherwise against the published bundle its headers name.
	roc_nightly = Script.roc_nightly!()?
	windows = Env.platform!().os == WINDOWS

	Env.with_temp_dir!(
		|temporary| {
			build_dir = Path.join(temporary, "build")
			Path.create_all!(build_dir)?
			bundle = match Script.env_str!("BUNDLE_PATH") {
				Ok(value) => Given(Path.utf8(value))
				Err(NotSet) => NotGiven
				Err(err) => return Err(err)
			}
			match Script.env_str!("EXAMPLES_ARCHIVE_DIR") {
				Ok(archive) => test_archive!(roc_nightly, Path.utf8(archive), bundle, build_dir, windows)
				Err(NotSet) => {
					apps = load_spec!("tests/spec.json", "examples")?
					match bundle {
						Given(path) => test_bundle!(roc_nightly, apps, path, temporary, build_dir, windows)
						NotGiven if windows => {
							# roc bundle is unavailable on Windows, so exercise the working tree.
							Script.info!("NOTE", "using the local package source because bundling is unavailable on Windows")?
							binaries = build_examples!(roc_nightly, apps, "examples", build_dir, windows, NoServer, WorkingTree)?
							run_cases!(apps, binaries, windows)
						}
						NotGiven => {
							bundle_dir = Path.join(temporary, "bundle")
							Script.roc_stable!()?.cmd(["scripts/build_bundle.roc"]).env("OUTPUT_DIR", Path.to_os_str(bundle_dir)).exec_cmd!()?
							match Path.list!(bundle_dir)? {
								[path] => test_bundle!(roc_nightly, apps, path, temporary, build_dir, windows)
								_ => Script.fail!("expected exactly one bundle in ${Path.display(bundle_dir)}")
							}
						}
					}
				}
				Err(err) => Err(err)
			}
		},
	)
}

test_archive! = |roc_nightly, archive, bundle, build_dir, windows| {
	# A published archive is immutable, so its sources are never rewritten or
	# reformatted here. Its own spec describes the release it was built from.
	examples = Path.join(archive, "examples")
	apps = load_spec!(Path.join(archive, "spec.json"), examples)?
	urls = Files.direct_roc_files!(examples)?.map_try!(|source| Ok(Text.dependency_values(Path.read_utf8!(source)?, "weaver")))?
	declared = match urls {
		[[url], .. as rest] if rest.all(|other| other == [url]) => url
		_ => return Script.fail!("every archived example must name the same single weaver bundle URL")
	}
	Script.info!("ARCHIVE", "examples declare ${declared}")?
	match bundle {
		NotGiven => {
			binaries = build_examples!(roc_nightly, apps, examples, build_dir, windows, NoServer, Archive([]))?
			run_cases!(apps, binaries, windows)
		}
		Given(path) => {
			# The declared URL is not published yet, so serve the candidate bundle
			# on loopback and tell the compiler to load it in place of that URL.
			bundle_bytes = Path.read_bytes!(path)?
			listener = Tcp.listen!("127.0.0.1", 0, 5_000)?
			url = "http://127.0.0.1:${listener.local_port!()?.to_str()}/${Files.name(path)}"
			Script.info!("BUNDLE", url)?
			replace = ["--replace-dep", OsStr.from_str(declared), OsStr.from_str(url)]
			binaries = build_examples!(roc_nightly, apps, examples, build_dir, windows, Server({ listener, bundle_bytes }), Archive(replace))?
			listener.close!()?
			run_cases!(apps, binaries, windows)
		}
	}
}

load_spec! = |spec_path, examples| {
	spec : { apps : List(App) }
	spec = Json.parse(Path.read_utf8!(spec_path)?).map_err(|err| InvalidSpec(err))?

	# Every example needs cases, so adding an example without them fails here.
	discovered = Files.direct_roc_files!(examples)?.map(|path| "examples/${Files.name(path)}")
	specified = spec.apps.map(|example| example.path)
	missing = discovered.keep_if(|path| !specified.contains(path))
	extra = specified.keep_if(|path| !discovered.contains(path))
	if !missing.is_empty() or !extra.is_empty() or specified.len() != discovered.len() {
		return Script.fail!("${Path.display(spec_path)} does not match ${Path.display(examples)}: missing=${Str.inspect(missing)}, extra=${Str.inspect(extra)}")
	}

	for example in spec.apps {
		if example.cases.is_empty() {
			return Script.fail!("${example.path}: at least one case is required")
		}
		for case in example.cases {
			if example.cases.count_if(|other| other.name == case.name) != 1 or case.name == "" {
				return Script.fail!("${example.path} [${case.name}]: every case needs a unique non-empty name")
			}
			if case.stdout.is_err() and case.stdout_contains.is_err() {
				return Script.fail!("${example.path} [${case.name}]: at least one output assertion is required")
			}
		}
	}
	Ok(spec.apps)
}

test_bundle! = |roc_nightly, apps, bundle, temporary, build_dir, windows| {
	# Roc fetches package dependencies by URL, so serve the candidate bundle on
	# loopback and point temporary copies of the examples at it.
	bundle_bytes = Path.read_bytes!(bundle)?
	listener = Tcp.listen!("127.0.0.1", 0, 5_000)?
	url = "http://127.0.0.1:${listener.local_port!()?.to_str()}/${Files.name(bundle)}"
	Script.info!("BUNDLE", url)?

	examples = Path.join(Path.join(temporary, "rewritten"), "examples")
	Path.create_all!(Path.join(temporary, "rewritten"))?
	Path.copy_dir!("examples", examples)?
	for source in Files.direct_roc_files!(examples)? {
		rewritten = Text.rewrite_dependency(Path.read_utf8!(source)?, "weaver", url)?
		if rewritten.contains("\r") {
			return Script.fail!("${Files.name(source)}: rewritten Roc source contains CR line endings")
		}
		Path.write_utf8!(source, rewritten)?
	}

	binaries = build_examples!(roc_nightly, apps, examples, build_dir, windows, Server({ listener, bundle_bytes }), WorkingTree)?
	listener.close!()?
	run_cases!(apps, binaries, windows)
}

build_examples! = |roc_nightly, apps, examples, build_dir, windows, server, kind| {
	Script.section!("EXAMPLES")?
	extra = match kind {
		WorkingTree => []
		Archive(args) => args
	}
	var $binaries = []
	for example in apps {
		filename = Str.drop_prefix(example.path, "examples/")
		source = Path.to_os_str(Path.join(examples, filename))
		binary = Path.join(build_dir, if windows "${Files.stem(filename)}.exe" else Files.stem(filename))
		match kind {
			WorkingTree => run_step!(roc_nightly, ["fmt", "--check", source], server)?
			# A later formatter must not fail an archive that cannot change.
			Archive(_) => {}
		}
		run_step!(roc_nightly, ["check", source, "--no-cache"].concat(extra), server)?
		run_step!(roc_nightly, ["test", source, "--no-cache"].concat(extra), server)?
		run_step!(roc_nightly, ["build", source, OsStr.from_str("--output=${Path.display(binary)}"), "--no-cache"].concat(extra), server)?
		$binaries = $binaries.append((example.path, binary))
	}
	Ok($binaries)
}

run_step! = |roc_nightly, args, server| {
	Stdout.line!("+ ${Str.join_with([roc_nightly.program()].concat(args).map(OsStr.display), " ")}")?
	child = roc_nightly.cmd(args).spawn!().map_err(|err| SpawnFailed(err))?
	output = wait_serving!(child, server)?
	match output.status {
		Exited(0) => Ok({})
		Exited(code) => Err(StepExited(args.map(OsStr.display), code))
		Signaled(signal) => Err(StepSignaled(args.map(OsStr.display), signal))
	}
}

wait_serving! : Cmd.Child, [NoServer, Server({ listener : Tcp.Listener, bundle_bytes : List(U8) })] => Try(Cmd.RunOutput, _)
wait_serving! = |child, server|
	match server {
		NoServer => child.wait!().map_err(|err| WaitFailed(err))
		Server({ listener, bundle_bytes }) =>
		# The compiler fetches the bundle while it runs. Poll so this process
		# can answer that request and watch for the child's exit without threads.
			match child.try_wait!().map_err(|err| WaitFailed(err))? {
				[output] => Ok(output)
				[_, _, ..] => Err(UnexpectedWaitResult)
				[] =>
					match listener.accept!(100) {
						Ok(stream) => {
							_ = stream.read_until!('\n', 65_536, 5_000)?
							stream.write_utf8!(http_ok_headers(List.len(bundle_bytes)), 5_000)?
							stream.write!(bundle_bytes, 30_000)?
							wait_serving!(child, server)
						}
						Err(TcpListenErr(TimedOut)) => wait_serving!(child, server)
						Err(err) => Err(ServeFailed(err))
					}
			}
	}

http_ok_headers : U64 -> Str
http_ok_headers = |content_length|
	# HTTP requires CRLF separators, which a multiline string would not produce.
	Str.join_with(
		[
			"HTTP/1.1 200 OK",
			"Content-Type: application/octet-stream",
			"Content-Length: ${content_length.to_str()}",
			"Connection: close",
			"",
			"",
		],
		"\r\n",
	)

run_cases! = |apps, binaries, windows| {
	Script.section!("SPEC CASES")?
	var $total = 0
	var $skipped = 0
	for example in apps {
		binary = match binaries.find_first(|(path, _)| path == example.path) {
			Ok((_, found)) => found
			Err(_) => return Script.fail!("${example.path}: no binary was built")
		}
		for case in example.cases {
			raw_args = (case.unix_args_hex ?? []).map_try(Text.from_hex)?
			if windows and !raw_args.is_empty() {
				Stdout.line!("SKIP ${example.path} [${case.name}]: raw Unix arguments are unavailable on Windows")?
				$skipped = $skipped + 1
			} else {
				Stdout.line!("CASE ${example.path} [${case.name}]")?
				run_case!(example.path, binary, case, raw_args)?
				$total = $total + 1
			}
		}
	}
	Stdout.line!(summary($total, $skipped))
}

summary : U64, U64 -> Str
summary = |total, skipped| "\nAll ${total.to_str()} spec cases passed (${skipped.to_str()} skipped)."

run_case! = |path, binary, case, raw_args| {
	label = "${path} [${case.name}]"
	args = (case.args ?? []).map(OsStr.from_str).concat(raw_args.map(OsStr.unix_bytes))
	output = Cmd.new(Path.to_os_str(binary))
		.args(args)
		.stdout(Capture)
		.stderr(Capture)
		.timeout_ms(10_000)
		.run!()
		.map_err(|err| CaseRunFailed(label, err))?
	stdout = Str.from_utf8_lossy(Text.normalize(output.stdout_bytes))
	stderr = Str.from_utf8_lossy(Text.normalize(output.stderr_bytes))
	streams = "\n--- stdout ---\n${stdout}\n--- stderr ---\n${stderr}"

	expected_exit = case.exit_code ?? 0
	match output.status {
		Exited(code) if code == expected_exit => {}
		Exited(code) => return Script.fail!("${label}: exited with ${code.to_str()}, expected ${expected_exit.to_str()}${streams}")
		Signaled(signal) => return Script.fail!("${label}: terminated by signal ${signal.to_str()}${streams}")
	}
	if stdout.contains("[ROC CRASHED]") or stderr.contains("[ROC CRASHED]") {
		return Script.fail!("${label}: Roc runtime crash${streams}")
	}
	match case.stdout {
		Ok(expected) => {
			wanted = Str.from_utf8_lossy(Text.normalize(Str.to_utf8(expected)))
			if stdout != wanted {
				return Script.fail!("${label}: unexpected stdout\n--- expected ---\n${wanted}\n--- actual ---\n${stdout}")
			}
		}
		Err(Missing) => {}
	}
	for expected in case.stdout_contains ?? [] {
		if !stdout.contains(expected) {
			return Script.fail!("${label}: missing stdout output ${Str.inspect(expected)}${streams}")
		}
	}
	# No case expects diagnostics on stderr, so any output there is a failure.
	if stderr != "" {
		return Script.fail!("${label}: unexpected stderr${streams}")
	}
	Ok({})
}
