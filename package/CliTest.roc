import Base exposing [ArgParserResult, CliConfig, SubcommandsConfig]
import Cli
import Opt
import Param
import SubCmd
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

NestedSub : [
	Leaf({ alpha : U64, data : Str }),
	Bare,
]

NestedTop : [
	Mid({ depth : Try(U64, [NoValue]), sc : Try(NestedSub, [NoSubcommand]) }),
	Other,
]

NestedRoot : {
	force : Bool,
	level : Try(U64, [NoValue]),
	sc : Try(NestedTop, [NoSubcommand]),
	file : Try(Str, [NoValue]),
	files : List(Str),
}

nested_parser : Cli.CliParser(NestedRoot)
nested_parser =
	Cli.assert_valid(
		Cli.finish(
			{
				force: Opt.flag({ short: "f", long: "force", help: "Force." }),
				level: Opt.maybe_u64({ short: "l", long: "level", help: "Level." }),
				sc: SubCmd.optional([mid_subcommand, SubCmd.empty({ name: "other", description: "Other.", value: Other })]),
				file: Param.maybe_str({ name: "file", help: "The file." }),
				files: Param.str_list({ name: "files", help: "More files." }),
			}.Cli,
			{ name: "app", version: "v1", authors: [], description: "", text_style: Plain },
		),
	)

mid_subcommand : SubCmd.SubcommandParserConfig(NestedTop)
mid_subcommand =
	SubCmd.finish(
		{
			depth: Opt.maybe_u64({ short: "d", long: "depth", help: "Depth." }),
			sc: SubCmd.optional([leaf_subcommand, SubCmd.empty({ name: "bare", description: "Bare.", value: Bare })]),
		}.Cli,
		{ name: "mid", description: "Middle.", mapper: |data| Mid(data) },
	)

leaf_subcommand : SubCmd.SubcommandParserConfig(NestedSub)
leaf_subcommand =
	SubCmd.finish(
		{
			alpha: Opt.u64({ short: "a", long: "alpha", help: "Alpha.", default: NoDefault }),
			data: Param.str({ name: "data", help: "Data.", default: NoDefault }),
		}.Cli,
		{ name: "leaf", description: "Leaf.", mapper: |data| Leaf(data) },
	)

nested_parse : List(Str) -> Try(NestedRoot, [Help(Str), Version(Str), InvalidUsage(Str)])
nested_parse = |args| Cli.parse_or_display_message(nested_parser, args, |arg| Utf8(arg))

## The usage error for `args` reports `problem` against `command`'s usage and help.
nested_usage_error : List(Str), Str, Str -> Bool
nested_usage_error = |args, problem, command|
	match nested_parse(args) {
		Err(InvalidUsage(message)) =>
			message.contains(problem)
				and message.contains("\nUsage:\n  ${command} ")
				and !(message.contains("\nUsage:\n  ${command} mid"))
				and !(message.contains("\nUsage:\n  ${command} leaf"))
				and (message.contains("Tip: Run `${command} --help`") or message.contains("Tip: Remove the extra value"))
		_other => False
	}

no_subcommand_root : NestedRoot
no_subcommand_root = { force: False, level: Err(NoValue), sc: Err(NoSubcommand), file: Err(NoValue), files: [] }

## A parent's flag after a subcommand's name is unknown to that subcommand.
expect {
	nested_usage_error(["mid", "-f"], "The argument \"-f\" was not recognized.", "app mid")
		and nested_usage_error(["mid", "--force"], "The argument \"--force\" was not recognized.", "app mid")
		and nested_usage_error(["other", "-f"], "The argument \"-f\" was not recognized.", "app other")
		and nested_usage_error(["mid", "-fd", "1"], "The argument \"-f\" was not recognized.", "app mid")
}

## A parent's value option after a subcommand's name is unknown to that subcommand.
expect {
	nested_usage_error(["mid", "-l", "3"], "The argument \"-l\" was not recognized.", "app mid")
		and nested_usage_error(["mid", "--level=3"], "The argument \"--level\" was not recognized.", "app mid")
}

## Options of every ancestor are unknown after a nested subcommand's name.
expect {
	nested_usage_error(["mid", "leaf", "-a", "1", "-f", "x"], "The argument \"-f\" was not recognized.", "app mid leaf")
		and nested_usage_error(["mid", "leaf", "-a", "1", "-d", "2", "x"], "The argument \"-d\" was not recognized.", "app mid leaf")
		and nested_usage_error(["mid", "bare", "-d", "2"], "The argument \"-d\" was not recognized.", "app mid bare")
}

## An unknown option after a nested subcommand's name is reported before its missing requirement.
expect {
	nested_usage_error(["mid", "leaf", "-f", "x"], "The argument \"-f\" was not recognized.", "app mid leaf")
		and nested_usage_error(["mid", "leaf", "--level", "1"], "The argument \"--level\" was not recognized.", "app mid leaf")
}

## A parameter after a subcommand's name is never given to a parent's parameters.
expect {
	nested_usage_error(["mid", "x"], "The parameter \"x\" was not expected.", "app mid")
		and nested_usage_error(["mid", "x", "y"], "The parameter \"x\" was not expected.", "app mid")
		and nested_usage_error(["other", "x"], "The parameter \"x\" was not expected.", "app other")
		and nested_usage_error(["mid", "bare", "x"], "The parameter \"x\" was not expected.", "app mid bare")
		and nested_usage_error(["mid", "leaf", "-a", "1", "one", "two"], "The parameter \"two\" was not expected.", "app mid leaf")
}

## After `--`, values that follow a subcommand's name still belong to it alone.
expect {
	nested_usage_error(["mid", "--", "x"], "The parameter \"x\" was not expected.", "app mid")
		and nested_usage_error(["mid", "leaf", "-a", "1", "--", "-x", "y"], "The parameter \"y\" was not expected.", "app mid leaf")
		and nested_parse(["mid", "leaf", "-a", "1", "--", "-x"])
			== Ok({ ..no_subcommand_root, sc: Ok(Mid({ depth: Err(NoValue), sc: Ok(Leaf({ alpha: 1, data: "-x" })) })) })
}

## A delimiter before a subcommand's name makes the name a parent parameter.
expect {
	nested_parse(["--", "mid", "-f"]) == Ok({ ..no_subcommand_root, file: Ok("mid"), files: ["-f"] })
}

## Parent options before a subcommand's name still reach the parent.
expect {
	nested_parse(["-f", "--level", "4", "mid", "-d", "2", "leaf", "-a", "1", "x"])
		== Ok({
			..no_subcommand_root,
			force: True,
			level: Ok(4),
			sc: Ok(Mid({ depth: Ok(2), sc: Ok(Leaf({ alpha: 1, data: "x" })) })),
		})
}

## A parent value option's value is never read as a subcommand's name.
expect {
	nested_parse(["-l", "1", "mid"]) == Ok({ ..no_subcommand_root, level: Ok(1), sc: Ok(Mid({ depth: Err(NoValue), sc: Err(NoSubcommand) })) })
		and (
			match nested_parse(["-l", "mid"]) {
				Err(InvalidUsage(message)) => message.contains("The value provided to -l/--level was not a valid number.\n\nUsage:\n  app ")
				_other => False
			}
		)
}

## A parameter before a subcommand's name keeps the name a parameter too.
expect {
	nested_parse(["file", "mid", "-f"]) == Ok({ ..no_subcommand_root, force: True, file: Ok("file"), files: ["mid"] })
}

## Help and version after a subcommand's name keep their precedence.
expect {
	help_for = |args|
		match nested_parse(args) {
			Err(Help(message)) => Ok(message.split_on("\n").first() ?? "")
			_other => Err(NotHelp)
		}

	help_for(["mid", "-f", "--help"]) == Ok("app mid v1")
		and help_for(["mid", "x", "-h"]) == Ok("app mid v1")
		and help_for(["mid", "leaf", "x", "y", "-h"]) == Ok("app mid leaf v1")
		and help_for(["-h", "mid", "x"]) == Ok("app v1")
		and nested_parse(["mid", "leaf", "-f", "--version"]) == Err(Version("v1"))
}

## A subcommand option before a nested subcommand's name stays with that subcommand.
expect {
	nested_parse(["mid", "--depth=3", "bare"])
		== Ok({ ..no_subcommand_root, sc: Ok(Mid({ depth: Ok(3), sc: Ok(Bare) })) })
}

LeftNested : { force : Bool, level : Try(U64, [NoValue]), sc : Try(NestedTop, [NoSubcommand]) }

## Whether the parent's options are combined left or right of each other, they
## stop at the subcommand's name.
expect {
	force = Opt.flag({ short: "f", long: "", help: "Force." })
	level = Opt.maybe_u64({ short: "l", long: "", help: "Level." })
	sc = SubCmd.optional([mid_subcommand])
	config = { name: "app", version: "", authors: [], description: "", text_style: Plain }
	left_nested : Cli.CliParser(LeftNested)
	left_nested =
		Cli.assert_valid(
			Cli.finish(
				Cli.map2(
					Cli.map2(force, level, |f, l| (f, l)),
					sc,
					|(f, l), s| { force: f, level: l, sc: s },
				),
				config,
			),
		)
	right_nested : Cli.CliParser(LeftNested)
	right_nested =
		Cli.assert_valid(
			Cli.finish(
				Cli.map2(force, Cli.map2(level, sc, |l, s| (l, s)), |f, (l, s)| { force: f, level: l, sc: s }),
				config,
			),
		)
	parse_both = |args| (
		Cli.parse_or_display_message(left_nested, args, |arg| Utf8(arg)),
		Cli.parse_or_display_message(right_nested, args, |arg| Utf8(arg)),
	)
	rejected = |args|
		match parse_both(args) {
			(Err(InvalidUsage(left)), Err(InvalidUsage(right))) => left == right and left.contains("\nUsage:\n  app mid ")
			_other => False
		}
	expected = { force: True, level: Ok(2), sc: Ok(Mid({ depth: Err(NoValue), sc: Err(NoSubcommand) })) }

	parse_both(["-l", "2", "-f", "mid"]) == (Ok(expected), Ok(expected))
		and rejected(["mid", "-f"])
		and rejected(["mid", "-l", "2"])
		and rejected(["-f", "mid", "-l", "2"])
}
