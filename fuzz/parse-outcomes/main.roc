app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
	weaver: "../../package/main.roc",
}

import fuzz.Fuzz
import weaver.Cli
import weaver.Opt
import weaver.Param

# Any command line given to a parser with options, flags, defaults and
# positional parameters must end in exactly one well-formed outcome: parsed
# data, the help page, the version, or a usage report naming the problem. The
# outcome must also not depend on whether a valid UTF-8 argument arrives as a
# `Str`, as Unix bytes or as Windows UTF-16. A command line only parses when
# every option it spells is declared: no empty long name such as `--=5` ever
# names an option, and no part of a short option group, such as a multibyte
# or invalid UTF-8 character, is silently dropped.
#
#     roc build --fuzz fuzz/parse-outcomes/main.roc --output=parse-outcomes
#     ./parse-outcomes run fuzz/parse-outcomes/corpus --time=60
#
# Every pull request replays the committed corpus; see scripts/check_all.roc.

Config : {
	verbose : U64,
	force : Bool,
	alpha : U64,
	beta : Try(Dec, [NoValue]),
	level : Try(I64, [NoValue]),
	name : Str,
	tags : List(Str),
	raw : Try(List(U8), [NoValue]),
	input : Str,
	output : Try(Str, [NoValue]),
	rest : List(Str),
}

Outcome : Try(Config, [Help(Str), Version(Str), InvalidUsage(Str)])

RawArg : [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]

cli_parser : Cli.CliParser(Config)
cli_parser =
	Cli.assert_valid(
		Cli.finish(
			{
				verbose: Opt.count({ short: "v", long: "verbose", help: "Say more." }),
				force: Opt.flag({ short: "f", long: "force", help: "Do it anyway." }),
				alpha: Opt.u64({ short: "a", long: "alpha", help: "Alpha level.", default: Value(7) }),
				beta: Opt.maybe_dec({ short: "b", long: "beta", help: "Beta level." }),
				level: Opt.maybe_i64({ short: "l", long: "", help: "Signed level." }),
				name: Opt.str({ short: "", long: "name", help: "Who to greet.", default: Value("anon") }),
				tags: Opt.str_list({ short: "t", long: "tag", help: "A tag; repeatable." }),
				raw: Opt.maybe_bytes({ short: "x", long: "raw", help: "Raw bytes." }),
				input: Param.str({ name: "input", help: "The input.", default: NoDefault }),
				output: Param.maybe_str({ name: "output", help: "The output." }),
				rest: Param.str_list({ name: "rest", help: "Everything else." }),
			}.Cli,
			{
				name: "fuzz-cli",
				version: "v9.9.9",
				authors: ["Fuzz <fuzz@example.com>"],
				description: "A command line parser that is fed arbitrary arguments.",
				text_style: Plain,
			},
		),
	)

## Split the fuzz input on NUL bytes, as a real argv would be split. Arguments
## that are valid UTF-8 arrive as `Utf8`, and the rest as Unix bytes.
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

parse_with : List(List(U8)), (List(U8) -> RawArg) -> Outcome
parse_with = |args, to_raw|
	Cli.parse_or_display_message(cli_parser, args, to_raw)

contains_bytes : List(U8), List(U8) -> Bool
contains_bytes = |haystack, needle|
	if needle.len() > haystack.len() {
		False
	} else if haystack.take_first(needle.len()) == needle {
		True
	} else {
		contains_bytes(haystack.drop_first(1), needle)
	}

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

## The short names `cli_parser` declares, which a parsed short option group
## may contain. Help and version never parse, so they are not among them.
declared_shorts : List(U8)
declared_shorts = Str.to_utf8("vfabltx")

## Whether an argument that the parser reads as a short option group, a
## single dash followed by anything but a second dash, consists only of
## declared short names.
short_group_is_declared : List(U8) -> Bool
short_group_is_declared = |arg|
	match arg {
		['-', second, .. as rest] if second != '-' => rest.prepend(second).all(|byte| declared_shorts.contains(byte))
		_ => True
	}

check_outcome : List(List(U8)), Outcome -> {}
check_outcome = |args, outcome| {
	before_delimiter = option_args(args)

	match outcome {
		Ok(config) =>
		# Positional parameters are always whole arguments.
			if before_delimiter.any(|arg| arg.starts_with(['-', '-', '='])) {
				crash "parsed a command line with an empty long option name"
			} else if !before_delimiter.all(short_group_is_declared) {
				crash "parsed a short option group with a member that is not a declared short option"
			} else if !args.any(|arg| arg == Str.to_utf8(config.input)) {
				crash "the input parameter is not one of the arguments"
			} else if !config.rest.all(|param| args.any(|arg| arg == Str.to_utf8(param))) {
				crash "a rest parameter is not one of the arguments"
			} else {
				{}
			}

		Err(Help(message)) =>
			if !before_delimiter.any(|arg| arg.contains('h')) {
				crash "help was shown without an argument naming it"
			} else if !message.starts_with("fuzz-cli v9.9.9\n") {
				crash "help does not start with the command name and version"
			} else if !message.contains("\n\nUsage:\n  fuzz-cli ") {
				crash "help does not contain the usage section"
			} else {
				{}
			}

		Err(Version(message)) =>
			if message != "v9.9.9" {
				crash "version message is not the configured version"
			} else if !before_delimiter.any(|arg| arg.contains('V') or contains_bytes(arg, Str.to_utf8("version"))) {
				crash "version was shown without an argument naming it"
			} else {
				{}
			}

		Err(InvalidUsage(message)) =>
			if !message.starts_with("┌") {
				crash "usage error does not start with its title frame"
			} else if !message.contains("\n\nUsage:\n  fuzz-cli ") {
				crash "usage error does not contain the usage section"
			} else if !message.contains("\n\nTip: ") {
				crash "usage error does not end with a tip"
			} else {
				{}
			}
	}
}

## Valid UTF-8 as Windows UTF-16 code units.
utf8_to_utf16 : List(U8) -> List(U16)
utf8_to_utf16 = |bytes| utf8_to_utf16_help(bytes, [])

utf8_to_utf16_help : List(U8), List(U16) -> List(U16)
utf8_to_utf16_help = |bytes, out|
	match bytes {
		[] => out
		[a, .. as rest] if a < 0x80 => utf8_to_utf16_help(rest, out.append(U8.to_u16(a)))
		[a, b, .. as rest] if a < 0xE0 => {
			code = (U8.to_u32(a) % 32) * 64 + (U8.to_u32(b) % 64)
			utf8_to_utf16_help(rest, out.append(U32.to_u16_wrap(code)))
		}

		[a, b, c, .. as rest] if a < 0xF0 => {
			code = ((U8.to_u32(a) % 16) * 4096) + ((U8.to_u32(b) % 64) * 64) + (U8.to_u32(c) % 64)
			utf8_to_utf16_help(rest, out.append(U32.to_u16_wrap(code)))
		}

		[a, b, c, d, .. as rest] => {
			code = ((U8.to_u32(a) % 8) * 262144) + ((U8.to_u32(b) % 64) * 4096) + ((U8.to_u32(c) % 64) * 64) + (U8.to_u32(d) % 64)
			offset = code - 0x10000
			high = 0xD800 + offset // 1024
			low = 0xDC00 + offset % 1024
			utf8_to_utf16_help(rest, out.append(U32.to_u16_wrap(high)).append(U32.to_u16_wrap(low)))
		}

		[_, ..] => out
	}

## Bytes options read the platform's raw units, so they legitimately differ
## between Unix and Windows; everything else must agree.
without_raw : Outcome -> Outcome
without_raw = |outcome|
	match outcome {
		Ok(config) => Ok({ ..config, raw: Err(NoValue) })
		Err(message) => Err(message)
	}

test : List(List(U8)) -> Fuzz.Outcome
test = |args| {
	natural = parse_with(args, natural_arg)
	check_outcome(args, natural)

	if parse_with(args, |bytes| UnixBytes(bytes)) != natural {
		crash "passing valid UTF-8 arguments as Unix bytes changed the outcome"
	}

	all_utf8 = args.all(|arg| Str.from_utf8(arg).is_ok())
	if all_utf8 and without_raw(parse_with(args, |bytes| WindowsU16s(utf8_to_utf16(bytes)))) != without_raw(natural) {
		crash "passing valid UTF-8 arguments as Windows UTF-16 changed the outcome"
	}

	Fuzz.keep
}

target = Fuzz.target_with({
	name: "parse-outcomes",
	generator: Fuzz.map(Fuzz.raw_bytes, generate),
	test,
	show: |args| Str.inspect(args.map(natural_arg)),
})
