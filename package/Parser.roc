import Arg exposing [Arg]

Parser := [].{
	ArgValue : Try(Arg, [NoValue])

	ParsedArg : [
		Short(Str),
		ShortGroup({ names : List(Str), complete : [Complete, Partial] }),
		Long({ name : Str, value : ArgValue }),
		Parameter(Arg),
	]

	parse_args : List(Arg) -> List(ParsedArg)
	parse_args = |args| {
		starting_state = { parsed_args: [], pass_through: KeepParsing }

		state_after = 
			args
				.drop_first(1)
				.fold(
					starting_state,
					|state, arg|
						match state.pass_through {
							KeepParsing => {
								parsed_arg = Parser.parse_arg(arg)

								match parsed_arg {
									Parameter(a) if a == double_dash_arg => {
										pass_through: PassThrough,
										parsed_args: state.parsed_args,
									}

									_other => {
										pass_through: KeepParsing,
										parsed_args: state.parsed_args.append(parsed_arg),
									}
								}
							}

							PassThrough => {
								pass_through: PassThrough,
								parsed_args: state.parsed_args.append(Parameter(arg)),
							}
						},
				)

		state_after.parsed_args
	}

	parse_arg : Arg -> ParsedArg
	parse_arg = |arg| {
		str_arg = 
			match Arg.to_str(arg) {
				Ok(str) => str
				Err(InvalidUtf8) => return Parameter(arg)
			}

		if str_arg == "-" {
			Parameter(single_dash_arg)
		} else if str_arg.starts_with("--") {
			rest = str_arg.drop_prefix("--")

			if rest == "" or rest.starts_with("-") {
				Parameter(arg)
			} else {
				Parser.parse_long_arg(rest)
			}
		} else if str_arg.starts_with("-") {
			Parser.construct_set_of_options(str_arg.drop_prefix("-"))
		} else {
			Parameter(arg)
		}
	}

	parse_long_arg : Str -> ParsedArg
	parse_long_arg = |arg|
		match arg.split_on("=") {
			[] => Long({ name: arg, value: Err(NoValue) })
			[option] => Long({ name: option, value: Err(NoValue) })
			[option, .. as value_parts] =>
				Long({ name: option, value: Ok(Arg.from_str(Str.join_with(value_parts, "="))) })
			}

	construct_set_of_options : Str -> ParsedArg
	construct_set_of_options = |combined| {
		options = 
			combined
				.to_utf8()
				.fold(
					[],
					|out, byte|
						match Str.from_utf8([byte]) {
							Ok(option) => out.append(option)
							Err(_) => out
						},
				)

		match options {
			[alone] => Short(alone)
			other => ShortGroup({ names: other, complete: Complete })
		}
	}
}

single_dash_arg : Arg
single_dash_arg = Arg.from_str("-")

double_dash_arg : Arg
double_dash_arg = Arg.from_str("--")

## A single dash remains a positional parameter.
expect {
	parsed = Parser.parse_arg(Arg.from_str("-"))

	parsed == Parameter(Arg.from_str("-"))
}

## A one-character short option parses as a short argument.
expect {
	parsed = Parser.parse_arg(Arg.from_str("-a"))

	parsed == Short("a")
}

## Adjacent short options parse as a complete short group.
expect {
	parsed = Parser.parse_arg(Arg.from_str("-abc"))

	parsed == ShortGroup({ names: ["a", "b", "c"], complete: Complete })
}

## A long option without an equals sign has no attached value.
expect {
	parsed = Parser.parse_arg(Arg.from_str("--abc"))

	parsed == Long({ name: "abc", value: Err(NoValue) })
}

## A long option preserves the value following its first equals sign.
expect {
	parsed = Parser.parse_arg(Arg.from_str("--abc=xyz"))

	parsed == Long({ name: "abc", value: Ok(Arg.from_str("xyz")) })
}

## Plain text parses as a positional parameter.
expect {
	parsed = Parser.parse_arg(Arg.from_str("123"))

	parsed == Parameter(Arg.from_str("123"))
}

## Parsing stops interpreting options after the double-dash delimiter.
expect {
	parsed = 
		Parser.parse_args(["this-wont-show", "-a", "123", "--passed", "-bcd", "xyz", "--", "--subject=world"].map(Arg.from_str))

	parsed
		== [
			Short("a"),
			Parameter(Arg.from_str("123")),
			Long({ name: "passed", value: Err(NoValue) }),
			ShortGroup({ names: ["b", "c", "d"], complete: Complete }),
			Parameter(Arg.from_str("xyz")),
			Parameter(Arg.from_str("--subject=world")),
		]
}
