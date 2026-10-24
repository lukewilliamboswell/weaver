app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
	weaver: "../../package/main.roc",
}

import fuzz.Fuzz
import weaver.Cli
import weaver.Opt
import weaver.Param

# Colour must only decorate. For any command line, the `Color` text style must
# reach the same outcome as `Plain`, its help and usage reports must contain
# nothing but complete SGR sequences beyond the plain text, and removing those
# sequences must give exactly the `Plain` text, which itself contains no
# escape characters. Arguments that themselves contain an escape character are
# echoed into reports verbatim, so for those only the outcomes are compared.
#
#     roc build --fuzz fuzz/render-styles/main.roc --output=render-styles
#     ./render-styles run fuzz/render-styles/corpus --time=60
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

color_parser : Cli.CliParser(Config)
color_parser = { ..cli_parser, text_style: Color }

escape : U8
escape = 27

## Remove complete `ESC [ digits-and-semicolons m` sequences, failing on any
## other use of the escape character.
strip_sgr : List(U8) -> Try(List(U8), [Malformed])
strip_sgr = |bytes| strip_sgr_help(bytes, [])

drop_sgr_parameters : List(U8) -> List(U8)
drop_sgr_parameters = |bytes|
	match bytes {
		[byte, .. as rest] if (byte >= '0' and byte <= '9') or byte == ';' => drop_sgr_parameters(rest)
		_ => bytes
	}

strip_sgr_help : List(U8), List(U8) -> Try(List(U8), [Malformed])
strip_sgr_help = |bytes, out|
	match bytes {
		[] => Ok(out)
		[byte, '[', .. as rest] if byte == escape => {
			match drop_sgr_parameters(rest) {
				['m', .. as after] => strip_sgr_help(after, out)
				_ => Err(Malformed)
			}
		}

		[byte, ..] if byte == escape => Err(Malformed)
		[byte, .. as rest] => strip_sgr_help(rest, out.append(byte))
	}

message_of : Outcome -> Try(Str, [NoMessage])
message_of = |outcome|
	match outcome {
		Ok(_) => Err(NoMessage)
		Err(Help(message)) | Err(Version(message)) | Err(InvalidUsage(message)) => Ok(message)
	}

same_kind : Outcome, Outcome -> Bool
same_kind = |plain, color|
	match (plain, color) {
		(Ok(a), Ok(b)) => a == b
		(Err(Help(_)), Err(Help(_))) => True
		(Err(Version(a)), Err(Version(b))) => a == b
		(Err(InvalidUsage(_)), Err(InvalidUsage(_))) => True
		_ => False
	}

test : List(List(U8)) -> Fuzz.Outcome
test = |args| {
	plain = Cli.parse_or_display_message(cli_parser, args, natural_arg)
	color = Cli.parse_or_display_message(color_parser, args, natural_arg)

	if !same_kind(plain, color) {
		crash "the Color and Plain styles reached different outcomes"
	}

	if !args.any(|arg| arg.contains(escape)) {
		match (message_of(plain), message_of(color)) {
			(Ok(plain_message), Ok(color_message)) => {
				plain_bytes = Str.to_utf8(plain_message)
				if plain_bytes.contains(escape) {
					crash "Plain output contains an escape character"
				}

				match strip_sgr(Str.to_utf8(color_message)) {
					Ok(stripped) if stripped == plain_bytes => {}
					Ok(_) => crash "Color output without its SGR sequences differs from Plain output"
					Err(Malformed) => crash "Color output contains an escape that is not a complete SGR sequence"
				}
			}

			_ => {}
		}
	}

	Fuzz.keep
}

target = Fuzz.target_with({
	name: "render-styles",
	generator: Fuzz.map(Fuzz.raw_bytes, generate),
	test,
	show: |args| Str.inspect(args.map(natural_arg)),
})
