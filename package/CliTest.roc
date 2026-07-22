import Arg
import Base exposing [ArgParserResult, SubcommandsConfig]
import Cli

CliTest := [].{}

test_config = {
	name: "basic-cli",
	version: "v1.0.0",
	authors: [],
	description: "",
	options: [],
	parameters: [],
	subcommands: SubcommandsConfig.NoSubcommands,
}

expect {
	parser = {
		config: test_config,
		parser: |args| ArgParserResult.SuccessfullyParsed(args.map(Arg.display)),
		text_style: Plain,
	}

	Cli.parse_or_display_message(parser, ["basic-cli", "ignored"], |arg| Unix(Str.to_utf8(arg)))
		== Ok(["basic-cli", "ignored"])
}

expect {
	parser = {
		config: test_config,
		parser: |_args| ArgParserResult.ShowHelp({ subcommand_path: ["basic-cli"] }),
		text_style: Plain,
	}

	Cli.parse_or_display_message(parser, ["basic-cli", "-h"], |arg| Unix(Str.to_utf8(arg)))
		== Err("basic-cli v1.0.0\n\nUsage:\n  basic-cli \n\n")
}

expect {
	parser = {
		config: test_config,
		parser: |_args| ArgParserResult.IncorrectUsage(UnrecognizedShortArg("x"), { subcommand_path: ["basic-cli"] }),
		text_style: Plain,
	}

	Cli.parse_or_display_message(parser, ["basic-cli", "-x"], |arg| Unix(Str.to_utf8(arg)))
		== Err("Error: The argument -x was not recognized.\n\nUsage:\n  basic-cli ")
}
