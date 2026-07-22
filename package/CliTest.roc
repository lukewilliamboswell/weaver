import Base exposing [ArgParserResult, CliConfig, SubcommandsConfig]
import Cli
import path.Path

CliTest := [].{}

test_config : CliConfig
test_config = {
	name: "basic-cli",
	version: "v1.0.0",
	authors: [],
	description: "",
	options: [],
	parameters: [],
	subcommands: SubcommandsConfig.NoSubcommands,
}

## Successful parses return the parser's transformed data.
expect {
	parser = {
		config: test_config,
		parser: |args| ArgParserResult.SuccessfullyParsed(args.map(Path.display)),
		text_style: Plain,
	}

	actual = Cli.parse_or_display_message(parser, ["basic-cli", "ignored"], |arg| Utf8(arg))?

	actual == ["basic-cli", "ignored"]
}

## Help requests render the root command's help text.
expect {
	parser = {
		config: test_config,
		parser: |_args| ArgParserResult.ShowHelp({ subcommand_path: ["basic-cli"] }),
		text_style: Plain,
	}

	Cli.parse_or_display_message(parser, ["basic-cli", "-h"], |arg| Utf8(arg))
		== Err("basic-cli v1.0.0\n\nUsage:\n  basic-cli \n\n")
}

## Incorrect usage includes both the parser error and usage text.
expect {
	parser = {
		config: test_config,
		parser: |_args| ArgParserResult.IncorrectUsage(UnrecognizedShortArg("x"), { subcommand_path: ["basic-cli"] }),
		text_style: Plain,
	}

	Cli.parse_or_display_message(parser, ["basic-cli", "-x"], |arg| Utf8(arg))
		== Err("Error: The argument -x was not recognized.\n\nUsage:\n  basic-cli ")
}
