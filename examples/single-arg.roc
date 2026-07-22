app [main!] {
	pf: platform "https://github.com/lukewilliamboswell/roc-platform-template-zig/releases/download/1.0.0/AnZoxzoGPtSGQ15EQh6pBeeaHJ7aizP9MQhK81dES3Uq.tar.zst",
	weaver: "../package/main.roc",
}

import pf.Stdout
import weaver.Cli
import weaver.Opt

SingleArgConfig : [Alpha(U64)]

main! : List(Str) => Try({}, _)
main! = |args| {
	match Cli.parse_or_display_message(cli_parser, args, str_to_raw_arg) {
		Err(message) => {
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

cli_parser : Cli.CliParser(SingleArgConfig)
cli_parser = 
	Cli.assert_valid(
		Cli.finish(
			Cli.map(
				Opt.u64({
					short: "a",
					long: "alpha",
					help: "Set the alpha level.",
					default: NoDefault,
				}),
				|alpha| Alpha(alpha),
			),
			{
				name: "single-arg",
				version: "v0.0.1",
				authors: [],
				description: "",
				text_style: Plain,
			},
		),
	)

str_to_raw_arg : Str -> [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]
str_to_raw_arg = |arg| UnixBytes(Str.to_utf8(arg))
