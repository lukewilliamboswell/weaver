import Base exposing [ArgParserResult, CliConfig, SubcommandsConfig]
import Cli
import Opt
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

	expected = 
		\\basic-cli v1.0.0
		\\
		\\Usage:
		\\  basic-cli
		\\
		\\

	Cli.parse_or_display_message(parser, ["basic-cli", "-h"], |arg| Utf8(arg)) == Err(Help(expected))
}

## Version requests are successful display outcomes, distinct from usage errors.
expect {
	parser = {
		config: test_config,
		parser: |_args| ArgParserResult.ShowVersion,
		text_style: Plain,
	}

	Cli.parse_or_display_message(parser, ["--version"], |arg| Utf8(arg))
		== Err(Version("v1.0.0"))
}

## Incorrect usage includes both the parser error and usage text.
expect {
	parser = {
		config: test_config,
		parser: |_args| ArgParserResult.IncorrectUsage(UnrecognizedShortArg("x"), { subcommand_path: ["basic-cli"] }),
		text_style: Plain,
	}

	expected = 
		\\┌───────────────────────┐
		\\│ UNRECOGNIZED ARGUMENT │
		\\└───────────────────────┘
		\\
		\\The argument -x was not recognized.
		\\
		\\Usage:
		\\  basic-cli
		\\
		\\Tip: Run `basic-cli --help` to see the available arguments.

	Cli.parse_or_display_message(parser, ["basic-cli", "-x"], |arg| Utf8(arg)) == Err(InvalidUsage(expected))
}

required_option_parser : Cli.CliParser({ alpha : U64 })
required_option_parser = 
	Cli.assert_valid(
		Cli.finish(
			Cli.map(
				Opt.u64({
					short: "a",
					long: "alpha",
					help: "Alpha.",
					default: NoDefault,
				}),
				|alpha| { alpha: alpha },
			),
			{
				name: "app",
				version: "",
				authors: [],
				description: "",
				text_style: Plain,
			},
		),
	)

## An unknown long option is reported before an unrelated missing requirement.
expect {
	match Cli.parse_or_display_message(required_option_parser, ["--wat"], |arg| Utf8(arg)) {
		Err(InvalidUsage(message)) => message.contains("The argument --wat was not recognized.")
		_other => False
	}
}

## An unknown member of a short group is reported before missing requirements.
expect {
	match Cli.parse_or_display_message(required_option_parser, ["-xz"], |arg| Utf8(arg)) {
		Err(InvalidUsage(message)) => message.contains("The argument -x was not recognized.")
		_other => False
	}
}

## A malformed known option still takes precedence over a later unknown option.
expect {
	match Cli.parse_or_display_message(required_option_parser, ["--alpha", "--wat"], |arg| Utf8(arg)) {
		Err(InvalidUsage(message)) => message.contains("Option -a/--alpha expects a number.")
		_other => False
	}
}

## Help keeps its established precedence over otherwise invalid arguments.
expect {
	match Cli.parse_or_display_message(required_option_parser, ["--help", "--wat"], |arg| Utf8(arg)) {
		Err(Help(message)) => message.starts_with("app\n\nUsage:")
		_other => False
	}
}
