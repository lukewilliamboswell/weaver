app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
	weaver: "../../package/main.roc",
}

import fuzz.Fuzz
import weaver.Cli
import weaver.Opt
import weaver.Param

# Every way of spelling the same command line must parse to exactly the values
# it spells. Long options with separate or attached values, short options,
# grouped short flags such as `-vvfn 42`, any order of different options, and
# parameters on either side of the options all parse alike; a number comes
# back as the value whose decimal text was given; and after `--` every
# argument, however option-like, is a parameter.
#
#     roc build --fuzz fuzz/equivalent-spellings/main.roc --output=equivalent-spellings
#     ./equivalent-spellings run fuzz/equivalent-spellings/corpus --time=60
#
# Every pull request replays the committed corpus; see scripts/check_all.roc.

Config : {
	verbose : U64,
	force : Bool,
	num : Try(U64, [NoValue]),
	tags : List(Str),
	files : List(Str),
}

## The values a command line spells, and how to spell them.
Case : {
	verbose : U64,
	force : Bool,
	num : Try(U64, [NoValue]),
	num_spelling : U8,
	separate_tags : Bool,
	tags : List(Str),
	leading : List(Str),
	passed : List(Str),
}

cli_parser : Cli.CliParser(Config)
cli_parser =
	Cli.assert_valid(
		Cli.finish(
			{
				verbose: Opt.count({ short: "v", long: "verbose", help: "Say more." }),
				force: Opt.flag({ short: "f", long: "force", help: "Do it anyway." }),
				num: Opt.maybe_u64({ short: "n", long: "num", help: "A number." }),
				tags: Opt.str_list({ short: "t", long: "tag", help: "A tag; repeatable." }),
				files: Param.str_list({ name: "files", help: "Files." }),
			}.Cli,
			{
				name: "spellings",
				version: "v1.0.0",
				authors: [],
				description: "",
				text_style: Plain,
			},
		),
	)

split_on_nul : List(U8) -> List(List(U8))
split_on_nul = |bytes| {
	state = bytes.fold(
		{ words: [], current: [] },
		|acc, byte|
			if byte == 0 {
				{ words: acc.words.append(acc.current), current: [] }
			} else {
				{ words: acc.words, current: acc.current.append(byte) }
			},
	)

	if bytes.is_empty() {
		[]
	} else {
		state.words.append(state.current)
	}
}

## Any printable ASCII text, including option-like text such as `--help`.
printable : List(U8) -> Str
printable = |bytes|
	Str.from_utf8(bytes.map(|byte| byte % 95 + 32)) ?? ""

## A non-empty lowercase word that can never be read as an option.
plain_word : List(U8) -> Str
plain_word = |bytes| {
	alphabet = Str.to_utf8("abcdefghijklmnopqrstuvwxyz0123456789")
	word = bytes.map(|byte| alphabet.get(U8.to_u64(byte % 36)) ?? 'a')

	if word.is_empty() {
		"x"
	} else {
		Str.from_utf8(word) ?? "x"
	}
}

## The first byte chooses which options appear and how they are spelled, the
## next eight are the number, the next two how many words are tags and how
## many are leading parameters, and the rest are NUL-separated words.
generate : List(U8) -> Case
generate = |bytes| {
	choice = bytes.get(0) ?? 0
	number = bytes.drop_first(1).take_first(8).fold(0, |acc, byte| acc * 256 + U8.to_u64(byte))
	tag_count = U8.to_u64((bytes.get(9) ?? 0) % 4)
	leading_count = U8.to_u64((bytes.get(10) ?? 0) % 4)
	words = split_on_nul(bytes.drop_first(11))

	{
		force: choice % 2 == 1,
		verbose: U8.to_u64((choice // 2) % 4),
		num: if (choice // 8) % 2 == 1 {
			Ok(number)
		} else {
			Err(NoValue)
		},
		num_spelling: (choice // 16) % 4,
		separate_tags: (choice // 64) % 2 == 1,
		tags: words.take_first(tag_count).map(printable),
		leading: words.drop_first(tag_count).take_first(leading_count).map(plain_word),
		passed: words.drop_first(tag_count + leading_count).map(printable),
	}
}

## Long options with separate values, then the parameters, then `--`.
canonical_args : Case -> List(Str)
canonical_args = |case| {
	verbose = List.repeat("--verbose", case.verbose)
	force = if case.force {
		["--force"]
	} else {
		[]
	}
	num =
		match case.num {
			Ok(n) => ["--num", n.to_str()]
			Err(NoValue) => []
		}
	tags = case.tags.map(|tag| "--tag=${tag}")

	verbose.concat(force).concat(num).concat(tags).concat(case.leading).append("--").concat(case.passed)
}

## The same values spelled another way: leading parameters first, then the
## tags, the number and the flags, using short and grouped forms.
variant_args : Case -> List(Str)
variant_args = |case| {
	tags =
		case.tags.join_map(
			|tag|
				# A separate value must not itself look like an option.
				if case.separate_tags and !tag.starts_with("-") {
					["-t", tag]
				} else {
					["--tag=${tag}"]
				},
		)
	flag_letters = Str.join_with(List.repeat("v", case.verbose), "").concat(
		if case.force {
			"f"
		} else {
			""
		},
	)
	separate_flags = List.repeat("-v", case.verbose).concat(
		if case.force {
			["-f"]
		} else {
			[]
		},
	)
	options =
		match (case.num, case.num_spelling) {
			(Ok(n), 0) => separate_flags.append("--num=${n.to_str()}")
			(Ok(n), 1) => ["-n", n.to_str()].concat(separate_flags)
			(Ok(n), 2) => ["-${flag_letters}n", n.to_str()]
			(Ok(n), _) => separate_flags.concat(["--num", n.to_str()])
			(Err(NoValue), _) if flag_letters.is_empty() => []
			(Err(NoValue), _) => ["-${flag_letters}"]
		}

	case.leading.concat(tags).concat(options).append("--").concat(case.passed)
}

test : Case -> Fuzz.Outcome
test = |case| {
	expected = Ok({
		verbose: case.verbose,
		force: case.force,
		num: case.num,
		tags: case.tags,
		files: case.leading.concat(case.passed),
	})

	if Cli.parse_or_display_message(cli_parser, canonical_args(case), |arg| Utf8(arg)) != expected {
		crash "the canonical spelling did not parse to the values it spells"
	}

	if Cli.parse_or_display_message(cli_parser, variant_args(case), |arg| Utf8(arg)) != expected {
		crash "the variant spelling did not parse to the values it spells"
	}

	Fuzz.keep
}

target = Fuzz.target_with({
	name: "equivalent-spellings",
	generator: Fuzz.map(Fuzz.raw_bytes, generate),
	test,
	show: |case| "canonical=${Str.inspect(canonical_args(case))} variant=${Str.inspect(variant_args(case))}",
})
