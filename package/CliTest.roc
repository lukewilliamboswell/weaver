import Base exposing [ArgParserResult, CliConfig, SubcommandsConfig]
import Cli
import Opt
import Param
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
		\\The argument "-x" was not recognized.
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
		Err(InvalidUsage(message)) => message.contains("The argument \"--wat\" was not recognized.")
		_other => False
	}
}

## An unknown member of a short group is reported before missing requirements.
expect {
	match Cli.parse_or_display_message(required_option_parser, ["-xz"], |arg| Utf8(arg)) {
		Err(InvalidUsage(message)) => message.contains("The argument \"-x\" was not recognized.")
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

## An option value that is not valid UTF-8 is reported against that option.
expect {
	args = [Utf8("-a"), UnixBytes([255])]
	match Cli.parse_or_display_message(required_option_parser, args, |arg| arg) {
		Err(InvalidUsage(message)) => message.contains("The value provided to -a/--alpha was not valid UTF-8.")
		_other => False
	}
}

file_parameter_parser : Cli.CliParser({ file : Str })
file_parameter_parser =
	Cli.assert_valid(
		Cli.finish(
			Cli.map(
				Param.str({ name: "file", help: "The file to process.", default: NoDefault }),
				|file| { file: file },
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

## A parameter that is not valid UTF-8 is reported against that parameter.
expect {
	args = [UnixBytes([255])]
	match Cli.parse_or_display_message(file_parameter_parser, args, |arg| arg) {
		Err(InvalidUsage(message)) => message.contains("The value provided to the 'file' parameter was not valid UTF-8.")
		_other => False
	}
}

## Arguments that contain escape sequences are never echoed raw, in either style.
expect {
	escape = "\u(001b)"
	color_parser = { ..required_option_parser, text_style: Color }
	cases = [["--${escape}[2Jpwned"], ["-${escape}"], ["-a${escape}", "1"], ["-a", "1", "x${escape}[31m"]]

	cases.all(
		|args| {
			plain = Cli.parse_or_display_message(required_option_parser, args, |arg| Utf8(arg))
			color = Cli.parse_or_display_message(color_parser, args, |arg| Utf8(arg))

			match (plain, color) {
				(Err(InvalidUsage(plain_message)), Err(InvalidUsage(color_message))) =>
					!(plain_message.contains(escape))
						and plain_message.contains("\\u(1b)")
						and !(color_message.contains("${escape}[2J"))
						and !(color_message.contains("${escape}[31m"))
						and !(color_message.contains("${escape}\""))
				_other => False
			}
		},
	)
}

## An unrecognized escape-laden long option is shown quoted and escaped.
expect {
	match Cli.parse_or_display_message(required_option_parser, ["--\u(001b)[2Jpwned"], |arg| Utf8(arg)) {
		Err(InvalidUsage(message)) => message.contains("The argument \"--\\u(1b)[2Jpwned\" was not recognized.")
		_other => False
	}
}

short_only_parser : Cli.CliParser({ alpha : U64 })
short_only_parser =
	Cli.assert_valid(
		Cli.finish(
			Cli.map(
				Opt.u64({ short: "a", long: "", help: "Alpha.", default: NoDefault }),
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

## An empty long name never sets an option without a long name, in any encoding.
expect {
	encodings : List(Str -> [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))])
	encodings = [
		|arg| Utf8(arg),
		|arg| UnixBytes(Str.to_utf8(arg)),
		|arg| WindowsU16s(Str.to_utf8(arg).map(U8.to_u16)),
	]

	["--=5", "--="].all(
		|arg|
			encodings.all(
				|encode|
					match Cli.parse_or_display_message(short_only_parser, [arg], encode) {
						Err(InvalidUsage(message)) => message.contains("The argument \"--=\" was not recognized.")
						_other => False
					},
			),
	)
}

## An empty long name with a value that is not valid text is reported the same way.
expect {
	args = [UnixBytes([0x2D, 0x2D, 0x3D, 0xFF]), WindowsU16s([0x002D, 0x002D, 0x003D, 0xD800])]

	args.all(
		|arg|
			match Cli.parse_or_display_message(short_only_parser, [arg], |a| a) {
				Err(InvalidUsage(message)) => message.contains("The argument \"--=\" was not recognized.")
				_other => False
			},
	)
}

flag_first_parser : Cli.CliParser({ verbose : Bool, alpha : U64 })
flag_first_parser =
	Cli.assert_valid(
		Cli.finish(
			{
				verbose: Opt.flag({ short: "v", long: "", help: "Verbose." }),
				alpha: Opt.u64({ short: "a", long: "", help: "Alpha.", default: Value(0) }),
			}.Cli,
			{ name: "app", version: "", authors: [], description: "", text_style: Plain },
		),
	)

value_first_parser : Cli.CliParser({ alpha : U64, verbose : Bool })
value_first_parser =
	Cli.assert_valid(
		Cli.finish(
			{
				alpha: Opt.u64({ short: "a", long: "", help: "Alpha.", default: Value(0) }),
				verbose: Opt.flag({ short: "v", long: "", help: "Verbose." }),
			}.Cli,
			{ name: "app", version: "", authors: [], description: "", text_style: Plain },
		),
	)

## A value option before a flag in a short group is rejected whichever is declared first.
expect {
	args = ["-av", "12"]
	flag_first = Cli.parse_or_display_message(flag_first_parser, args, |arg| Utf8(arg))
	value_first = Cli.parse_or_display_message(value_first_parser, args, |arg| Utf8(arg))

	match (flag_first, value_first) {
		(Err(InvalidUsage(_)), Err(InvalidUsage(message))) =>
			message.contains("Option -a must be last in the short option group \"-av\".")
		_other => False
	}
}

## A value option last in a short group is accepted whichever is declared first.
expect {
	args = ["-va", "12"]
	flag_first = Cli.parse_or_display_message(flag_first_parser, args, |arg| Utf8(arg))
	value_first = Cli.parse_or_display_message(value_first_parser, args, |arg| Utf8(arg))

	flag_first == Ok({ verbose: True, alpha: 12 }) and value_first == Ok({ alpha: 12, verbose: True })
}

## A flag repeated after a value option still leaves the value option not last.
expect {
	args = ["-vav", "12"]

	match (Cli.parse_or_display_message(flag_first_parser, args, |arg| Utf8(arg)), Cli.parse_or_display_message(value_first_parser, args, |arg| Utf8(arg))) {
		(Err(InvalidUsage(_)), Err(InvalidUsage(_))) => True
		_other => False
	}
}

force_parser : Cli.CliParser({ force : Bool, file : Str })
force_parser =
	Cli.assert_valid(
		Cli.finish(
			{
				force: Opt.flag({ short: "f", long: "", help: "Force." }),
				file: Param.str({ name: "file", help: "The file.", default: NoDefault }),
			}.Cli,
			{ name: "app", version: "", authors: [], description: "", text_style: Plain },
		),
	)

unrecognized_message : List([Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]), Str -> Bool
unrecognized_message = |args, shown| {
	match Cli.parse_or_display_message(force_parser, args, |arg| arg) {
		Err(InvalidUsage(message)) => message.contains("The argument \"${shown}\" was not recognized.")
		_other => False
	}
}

## A multibyte character in a short group is reported, not dropped.
expect {
	unrecognized_message([Utf8("-fé"), Utf8("in")], "-é")
		and unrecognized_message([Utf8("-é"), Utf8("in")], "-é")
		and unrecognized_message([UnixBytes(Str.to_utf8("-fé")), Utf8("in")], "-é")
}

## Invalid text in a short group is reported, not dropped or read as a parameter.
expect {
	unrecognized_message([UnixBytes([0x2D, 0x66, 0xC3]), Utf8("in")], "-\u(FFFD)")
		and unrecognized_message([WindowsU16s([0x002D, 0x0066, 0xDC00]), Utf8("in")], "-\u(FFFD)")
		and unrecognized_message([UnixBytes([0x2D, 0xFF])], "-\u(FFFD)")
}
