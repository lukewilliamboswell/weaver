app [main!] {
	pf: platform "https://github.com/lukewilliamboswell/roc-platform-template-zig/releases/download/1.0.0/AnZoxzoGPtSGQ15EQh6pBeeaHJ7aizP9MQhK81dES3Uq.tar.zst",
	weaver: "../package/main.roc",
}

import pf.Stdout
import weaver.Arg
import weaver.Cli
import weaver.Opt
import weaver.Param

BasicConfig : {
	alpha : U64,
	force : Bool,
	file : Try(Str, [NoValue]),
	files : List(Str),
}

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

cli_parser : Cli.CliParser(BasicConfig)
cli_parser = 
	Cli.assert_valid(
		Cli.finish(
			{
				alpha: Opt.u64({
					short: "a",
					long: "",
					help: "Set the alpha level.",
					default: NoDefault,
				}),
				force: Opt.flag({
					short: "f",
					long: "",
					help: "Force the task to complete.",
				}),
				file: Param.maybe_str({
					name: "file",
					help: "The file to process.",
				}),
				files: Param.str_list({
					name: "files",
					help: "The rest of the files.",
				}),
			}.Cli,
			{
				name: "basic",
				version: "v0.0.1",
				authors: ["Some One <some.one@mail.com>"],
				description: "This is a basic example of what you can build with Weaver. You get safe parsing, useful error messages, and help pages all for free!",
				text_style: Plain,
			},
		),
	)

str_to_raw_arg : Str -> [Unix(List(U8)), Windows(List(U16))]
str_to_raw_arg = |arg| Arg.to_raw_arg(Arg.from_str(arg))
