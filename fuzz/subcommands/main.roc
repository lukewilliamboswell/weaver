app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
	weaver: "../../package/main.roc",
}

import fuzz.Fuzz
import weaver.Cli
import weaver.Opt
import weaver.Param
import weaver.SubCmd

# Any command line given to a parser with nested subcommands must end in
# exactly one well-formed outcome. Help and usage reports must describe a
# command path that really exists and that the arguments really named, in
# order, and parsed subcommand data must come from the arguments given. The
# outcome must not depend on whether valid UTF-8 arrives as a `Str` or as
# Unix bytes. Nothing parses unless every option it spells is declared
# somewhere on the command path: an empty long name such as `--=5` never
# names an option, and no member of a short option group is dropped.
# Arguments after a subcommand's name belong to that subcommand alone: a
# parsed parent never takes an option or parameter from after the name of the
# subcommand it called, so the root's data comes only from the arguments
# before the first subcommand name, and `s1`'s only from those between its
# name and its sub-subcommand's.
#
#     roc build --fuzz fuzz/subcommands/main.roc --output=subcommands
#     ./subcommands run fuzz/subcommands/corpus --time=60
#
# Every pull request replays the committed corpus; see scripts/check_all.roc.

SubSubcommandConfig : [
	SS1({ a : U64, b : U64 }),
	SS2({ a : U64, c : U64, data : Str }),
]

FirstSubcommandConfig : {
	d : Try(U64, [NoValue]),
	volume : Try(U64, [NoValue]),
	sc : Try(SubSubcommandConfig, [NoSubcommand]),
}

SubcommandConfig : [
	S1(FirstSubcommandConfig),
	S2([DFlag(Try(U64, [NoValue]))]),
]

RootConfig : {
	force : Bool,
	sc : Try(SubcommandConfig, [NoSubcommand]),
	file : Try(Str, [NoValue]),
	files : List(Str),
}

Outcome : Try(RootConfig, [Help(Str), Version(Str), InvalidUsage(Str)])

RawArg : [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]

cli_parser : Cli.CliParser(RootConfig)
cli_parser =
	Cli.assert_valid(
		Cli.finish(
			{
				force: Opt.flag({ short: "f", long: "", help: "Force the task to complete." }),
				sc: SubCmd.optional([subcommand_parser1, subcommand_parser2]),
				file: Param.maybe_str({ name: "file", help: "The file to process." }),
				files: Param.str_list({ name: "files", help: "The rest of the files." }),
			}.Cli,
			{
				name: "subcommands",
				version: "v0.0.1",
				authors: ["Some One <some.one@mail.com>"],
				description: "Nested subcommands fed arbitrary arguments.",
				text_style: Plain,
			},
		),
	)

subcommand_parser1 : SubCmd.SubcommandParserConfig(SubcommandConfig)
subcommand_parser1 =
	SubCmd.finish(
		{
			d: Opt.maybe_u64({ short: "d", long: "", help: "A flag that does not overlap with s2." }),
			volume: Opt.maybe_u64({ short: "v", long: "volume", help: "How loud to grind the gears." }),
			sc: SubCmd.optional([sub_subcommand_parser1, sub_subcommand_parser2]),
		}.Cli,
		{ name: "s1", description: "A first subcommand.", mapper: |data| S1(data) },
	)

subcommand_parser2 : SubCmd.SubcommandParserConfig(SubcommandConfig)
subcommand_parser2 =
	SubCmd.finish(
		Cli.map(
			Opt.maybe_u64({ short: "d", long: "", help: "This does not overlap with s1's -d flag." }),
			|d_flag| DFlag(d_flag),
		),
		{ name: "s2", description: "Another subcommand.", mapper: |data| S2(data) },
	)

sub_subcommand_parser1 : SubCmd.SubcommandParserConfig(SubSubcommandConfig)
sub_subcommand_parser1 =
	SubCmd.finish(
		{
			a: Opt.u64({ short: "a", long: "", help: "A short flag.", default: NoDefault }),
			b: Opt.u64({ short: "b", long: "", help: "Another short flag.", default: NoDefault }),
		}.Cli,
		{ name: "ss1", description: "A sub-subcommand.", mapper: |data| SS1(data) },
	)

sub_subcommand_parser2 : SubCmd.SubcommandParserConfig(SubSubcommandConfig)
sub_subcommand_parser2 =
	SubCmd.finish(
		{
			a: Opt.u64({ short: "a", long: "", help: "Set the alpha level.", default: NoDefault }),
			c: Opt.u64({ short: "c", long: "create", help: "Create a doohickey.", default: NoDefault }),
			data: Param.str({ name: "data", help: "Data to manipulate.", default: NoDefault }),
		}.Cli,
		{ name: "ss2", description: "Another sub-subcommand.", mapper: |data| SS2(data) },
	)

## Every command path the parser declares.
command_paths : List(List(Str))
command_paths = [[], ["s1"], ["s2"], ["s1", "ss1"], ["s1", "ss2"]]

## Split the fuzz input on NUL bytes, as a real argv would be split.
generate : List(U8) -> List(List(U8))
generate = |bytes| {
	state = bytes.fold(
		{ args: [], current: [] },
		|acc, byte|
			if byte == 0 {
				{ args: acc.args.append(acc.current), current: [] }
			} else {
				{ args: acc.args, current: acc.current.append(byte) }
			},
	)

	if bytes.is_empty() {
		[]
	} else {
		state.args.append(state.current)
	}
}

natural_arg : List(U8) -> RawArg
natural_arg = |bytes|
	match Str.from_utf8(bytes) {
		Ok(str) => Utf8(str)
		Err(_) => UnixBytes(bytes)
	}

## Whether `names` appear in `args` in order, each as a whole argument.
named_in_order : List(List(U8)), List(Str) -> Bool
named_in_order = |args, names|
	match names {
		[] => True
		[first, .. as rest] =>
			match args {
				[] => False
				[arg, .. as remaining] =>
					if arg == Str.to_utf8(first) {
						named_in_order(remaining, rest)
					} else {
						named_in_order(remaining, names)
					}
			}
	}

## The declared command paths whose usage line the message shows, and which
## the arguments named in order.
described_paths : List(List(U8)), Str -> List(List(Str))
described_paths = |args, message|
	command_paths.keep_if(
		|path| {
			command = Str.join_with(["subcommands"].concat(path), " ")
			usage_line = "\nUsage:\n  ${command}"
			(message.contains("${usage_line} ") or message.contains("${usage_line}\n") or message.ends_with(usage_line))
				and named_in_order(args, path)
		},
	)

## The arguments the parser reads as options: everything before the first `--`.
option_args : List(List(U8)) -> List(List(U8))
option_args = |args|
	match args {
		[] => []
		[first, .. as rest] =>
			if first == ['-', '-'] {
				[]
			} else {
				option_args(rest).prepend(first)
			}
	}

## Every short name declared anywhere in `cli_parser`, apart from help and
## version, which never parse.
declared_shorts : List(U8)
declared_shorts = Str.to_utf8("fdvabc")

## Whether an argument read as a short option group, a single dash followed
## by anything but a second dash, consists only of declared short names.
short_group_is_declared : List(U8) -> Bool
short_group_is_declared = |arg|
	match arg {
		['-', second, .. as rest] if second != '-' => rest.prepend(second).all(|byte| declared_shorts.contains(byte))
		_ => True
	}

## Whether an argument read as a short option or group spells `letter`.
spells_short : List(U8), U8 -> Bool
spells_short = |arg, letter|
	match arg {
		['-', second, .. as rest] if second != '-' => rest.prepend(second).contains(letter)
		_ => False
	}

## The index of the first argument after `start` that is exactly `name`.
index_of_name : List(List(U8)), Str, U64 -> U64
index_of_name = |args, name, start|
	match args.get(start) {
		Err(_) => start
		Ok(arg) =>
			if arg == Str.to_utf8(name) {
				start
			} else {
				index_of_name(args, name, start + 1)
			}
	}

## Check that each command on the selected path only took data from the
## arguments between its own name and the next subcommand's name.
check_scope : List(List(U8)), RootConfig, List(Str) -> {}
check_scope = |args, config, path|
	match path {
		[] => {}
		[first, .. as nested] => {
			first_index = index_of_name(args, first, 0)
			root_args = args.take_first(first_index)
			root_spells_force = root_args.any(|arg| spells_short(arg, 'f'))

			if config.file != Err(NoValue) or !config.files.is_empty() {
				crash "a root parameter was taken from after a subcommand's name"
			} else if config.force and !root_spells_force {
				crash "the root flag was taken from after a subcommand's name"
			} else if !config.force and root_spells_force {
				crash "the root flag before a subcommand's name was lost"
			} else {
				match (nested, config.sc) {
					([second], Ok(S1({ d, volume, sc }))) => {
						second_index = index_of_name(args, second, first_index + 1)
						s1_args = args.sublist({ start: first_index + 1, len: second_index - first_index - 1 })
						ss_args = args.drop_first(second_index + 1)
						s1_spells_d = s1_args.any(|arg| spells_short(arg, 'd'))
						s1_spells_volume = s1_args.any(|arg| spells_short(arg, 'v') or arg.starts_with(Str.to_utf8("--volume")))
						data_from_ss =
							match sc {
								Ok(SS2({ data, .. })) => ss_args.keep_oks(Str.from_utf8).contains(data)
								_ => True
							}

						if d != Err(NoValue) and !s1_spells_d {
							crash "an s1 option was taken from after a sub-subcommand's name"
						} else if volume != Err(NoValue) and !s1_spells_volume {
							crash "an s1 option was taken from after a sub-subcommand's name"
						} else if !data_from_ss {
							crash "ss2 data is not one of the arguments after its name"
						} else {
							{}
						}
					}

					_ => {}
				}
			}
		}
	}

check_outcome : List(List(U8)), Outcome -> {}
check_outcome = |args, outcome|
	match outcome {
		Ok(config) => {
			arg_strs = args.keep_oks(Str.from_utf8)
			came_from_args = |value| arg_strs.contains(value)
			path =
				match config.sc {
					Err(NoSubcommand) => []
					Ok(S2(_)) => ["s2"]
					Ok(S1({ sc: Err(NoSubcommand), .. })) => ["s1"]
					Ok(S1({ sc: Ok(SS1(_)), .. })) => ["s1", "ss1"]
					Ok(S1({ sc: Ok(SS2({ data, .. })), .. })) => {
						if !came_from_args(data) {
							crash "ss2 data is not one of the arguments"
						}
						["s1", "ss2"]
					}
				}

			before_delimiter = option_args(args)

			if before_delimiter.any(|arg| arg.starts_with(['-', '-', '='])) {
				crash "parsed a command line with an empty long option name"
			} else if !before_delimiter.all(short_group_is_declared) {
				crash "parsed a short option group with a member that is not a declared short option"
			} else if !named_in_order(args, path) {
				crash "parsed a subcommand the arguments did not name"
			} else if !config.files.all(came_from_args) {
				crash "a files parameter is not one of the arguments"
			} else {
				match config.file {
					Ok(file) if !came_from_args(file) => crash "the file parameter is not one of the arguments"
					_ => check_scope(args, config, path)
				}
			}
		}

		Err(Help(message)) => {
			paths = described_paths(args, message)
			# Shorter paths' usage lines are prefixes of longer ones, so the
			# header must name the longest one described.
			longest = paths.fold(
				[],
				|best, path| if path.len() > best.len() {
					path
				} else {
					best
				},
			)
			command = Str.join_with(["subcommands"].concat(longest), " ")
			matches_header = message.starts_with("${command} v0.0.1\n")
			if paths.is_empty() {
				crash "help does not describe a command path the arguments named"
			} else if !matches_header {
				crash "help does not start with the described command path and version"
			} else {
				{}
			}
		}

		Err(Version(message)) =>
			if message != "v0.0.1" {
				crash "version message is not the configured version"
			} else {
				{}
			}

		Err(InvalidUsage(message)) =>
			if !message.starts_with("┌") {
				crash "usage error does not start with its title frame"
			} else if described_paths(args, message).is_empty() {
				crash "usage error does not describe a command path the arguments named"
			} else if !message.contains("\n\nTip: ") {
				crash "usage error does not end with a tip"
			} else {
				{}
			}
	}

test : List(List(U8)) -> Fuzz.Outcome
test = |args| {
	natural = Cli.parse_or_display_message(cli_parser, args, natural_arg)
	check_outcome(args, natural)

	if Cli.parse_or_display_message(cli_parser, args, |bytes| UnixBytes(bytes)) != natural {
		crash "passing valid UTF-8 arguments as Unix bytes changed the outcome"
	}

	Fuzz.keep
}

target = Fuzz.target_with({
	name: "subcommands",
	generator: Fuzz.map(Fuzz.raw_bytes, generate),
	test,
	show: |args| Str.inspect(args.map(natural_arg)),
})
