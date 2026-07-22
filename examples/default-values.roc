app [main!] {
	pf: platform "https://github.com/lukewilliamboswell/roc-platform-template-zig/releases/download/1.0.0/AnZoxzoGPtSGQ15EQh6pBeeaHJ7aizP9MQhK81dES3Uq.tar.zst",
	weaver: "../package/main.roc",
}

import pf.Stdout
import weaver.Cli
import weaver.Opt
import weaver.Param

DefaultValuesConfig : { alpha : U64, beta : Dec, file : Str }

main! : List(Str) => Try({}, _)
main! = |args| {
	match Cli.parse_or_display_message(cli_parser, args.drop_first(1), str_to_raw_arg) {
		Err(Help(message)) => {
			Stdout.line!(message)?
			Ok({})
		}

		Err(Version(message)) => {
			Stdout.line!(message)?
			Ok({})
		}

		Err(InvalidUsage(message)) => {
			Stdout.line!(message)?
			Err(Exit(1))
		}

		Ok(data) => {
			Stdout.line!("Successfully parsed! Here's what I got:")?
			Stdout.line!("")?
			Stdout.line!(Str.inspect(data))?

			Ok({})
		}
	}
}

cli_parser : Cli.CliParser(DefaultValuesConfig)
cli_parser = 
	Cli.assert_valid(
		Cli.finish(
			{
				alpha: Opt.u64({
					short: "a",
					long: "alpha",
					help: "Set the alpha level. [default: 123]",
					default: Value(123),
				}),
				beta: Opt.dec({
					short: "b",
					long: "beta",
					help: "Set the beta level. [default: 3.14]",
					default: Generate(|{}| 3.14),
				}),
				file: Cli.map(
					Param.maybe_str({
						name: "file",
						help: "The file to process. [default: NONE]",
					}),
					maybe_file_default,
				),
			}.Cli,
			{
				name: "default-values",
				version: "v0.0.1",
				authors: [],
				description: "",
				text_style: Plain,
			},
		),
	)

maybe_file_default : Try(Str, [NoValue]) -> Str
maybe_file_default = |file|
	match file {
		Ok(path) => path
		Err(NoValue) => "NONE"
	}

str_to_raw_arg : Str -> [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]
str_to_raw_arg = |arg| UnixBytes(Str.to_utf8(arg))
