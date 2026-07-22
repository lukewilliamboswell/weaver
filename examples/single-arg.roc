app [main!] {
	pf: platform "https://github.com/lukewilliamboswell/roc-platform-template-zig/releases/download/1.0.0/AnZoxzoGPtSGQ15EQh6pBeeaHJ7aizP9MQhK81dES3Uq.tar.zst",
	weaver: "../package/main.roc",
}

import pf.Stdout
import weaver.Arg
import weaver.Cli
import weaver.Opt

main! : List(Str) => Try({}, [Exit(I32), StdoutErr(Str), ..])
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

str_to_raw_arg : Str -> [Unix(List(U8)), Windows(List(U16))]
str_to_raw_arg = |arg| Arg.to_raw_arg(Arg.from_str(arg))
