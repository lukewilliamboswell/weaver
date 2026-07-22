import path.Path

Parser := [].{
	ArgValue : Try(Path, [NoValue])

	ParsedArg : [
		Short(Str),
		ShortGroup({ names : List(Str), complete : [Complete, Partial] }),
		Long({ name : Str, value : ArgValue }),
		Parameter(Path),
		PassedThrough(Path),
	]

	parse_args : List(Path) -> List(ParsedArg)
	parse_args = |args| {
		starting_state = { parsed_args: [], pass_through: KeepParsing }

		state_after = 
			args
				.fold(
					starting_state,
					|state, arg|
						match state.pass_through {
							KeepParsing => {
								parsed_arg = Parser.parse_arg(arg)

								match parsed_arg {
									Parameter(a) if Path.to_str(a) == Ok("--") => {
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
								parsed_args: state.parsed_args.append(PassedThrough(arg)),
							}
						},
				)

		state_after.parsed_args
	}

	parse_arg : Path -> ParsedArg
	parse_arg = |arg| {
		match Path.to_str(arg) {
			Ok(str_arg) => Parser.parse_decoded_arg(arg, str_arg)
			Err(_) =>
				match Path.to_raw(arg) {
					UnixBytes(bytes) =>
						match parse_raw_unix_long_arg(bytes) {
							Ok(parsed) => parsed
							Err(NotRawLong) => Parameter(arg)
						}

					WindowsU16s(code_units) =>
						match parse_raw_windows_long_arg(code_units) {
							Ok(parsed) => parsed
							Err(NotRawLong) => Parameter(arg)
						}

					Utf8(_) => Parameter(arg)
				}
			}
	}

	parse_decoded_arg : Path, Str -> ParsedArg
	parse_decoded_arg = |arg, str_arg| {
		if str_arg == "-" {
			Parameter(arg)
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
				Long({ name: option, value: Ok(Path.utf8(Str.join_with(value_parts, "="))) })
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

parse_raw_unix_long_arg : List(U8) -> Try(Parser.ParsedArg, [NotRawLong])
parse_raw_unix_long_arg = |bytes|
	match bytes {
		[45, 45, .. as rest] => {
			{ name_units, value_units } = split_u8_at_equals(rest, [])?
			name =
				match Str.from_utf8(name_units) {
					Ok(value) => value
					Err(_) => return Err(NotRawLong)
				}

			if name == "" or name.starts_with("-") {
				Err(NotRawLong)
			} else {
				Ok(Long({ name, value: Ok(Path.from_raw(UnixBytes(value_units))) }))
			}
		}

		_other => Err(NotRawLong)
	}

parse_raw_windows_long_arg : List(U16) -> Try(Parser.ParsedArg, [NotRawLong])
parse_raw_windows_long_arg = |code_units|
	match code_units {
		[45, 45, .. as rest] => {
			{ name_units, value_units } = split_u16_at_equals(rest, [])?
			name =
				match Path.to_str(Path.from_raw(WindowsU16s(name_units))) {
					Ok(value) => value
					Err(_) => return Err(NotRawLong)
				}

			if name == "" or name.starts_with("-") {
				Err(NotRawLong)
			} else {
				Ok(Long({ name, value: Ok(Path.from_raw(WindowsU16s(value_units))) }))
			}
		}

		_other => Err(NotRawLong)
	}

split_u8_at_equals : List(U8), List(U8) -> Try({ name_units : List(U8), value_units : List(U8) }, [NotRawLong])
split_u8_at_equals = |units, name_units|
	match units {
		[] => Err(NotRawLong)
		[61, .. as value_units] => Ok({ name_units, value_units })
		[unit, .. as rest] => split_u8_at_equals(rest, name_units.append(unit))
	}

split_u16_at_equals : List(U16), List(U16) -> Try({ name_units : List(U16), value_units : List(U16) }, [NotRawLong])
split_u16_at_equals = |units, name_units|
	match units {
		[] => Err(NotRawLong)
		[61, .. as value_units] => Ok({ name_units, value_units })
		[unit, .. as rest] => split_u16_at_equals(rest, name_units.append(unit))
	}

## A single dash remains a positional parameter.
expect {
	parsed = Parser.parse_arg(Path.utf8("-"))

	parsed == Parameter(Path.utf8("-"))
}

## Delimiter recognition is independent of the platform's raw string representation.
expect {
	delimiter = Path.from_raw(UnixBytes(Str.to_utf8("--")))
	option_like_value = Path.from_raw(WindowsU16s([0x002D, 0x0078]))

	Parser.parse_args([delimiter, option_like_value]) == [PassedThrough(option_like_value)]
}

## Parsing preserves the first argument; callers own any executable-path removal.
expect {
	first = Path.utf8("first")
	second = Path.utf8("second")

	Parser.parse_args([first, second]) == [Parameter(first), Parameter(second)]
}

## A one-character short option parses as a short argument.
expect {
	parsed = Parser.parse_arg(Path.utf8("-a"))

	parsed == Short("a")
}

## Adjacent short options parse as a complete short group.
expect {
	parsed = Parser.parse_arg(Path.utf8("-abc"))

	parsed == ShortGroup({ names: ["a", "b", "c"], complete: Complete })
}

## A long option without an equals sign has no attached value.
expect {
	parsed = Parser.parse_arg(Path.utf8("--abc"))

	parsed == Long({ name: "abc", value: Err(NoValue) })
}

## A long option preserves the value following its first equals sign.
expect {
	parsed = Parser.parse_arg(Path.utf8("--abc=xyz"))

	parsed == Long({ name: "abc", value: Ok(Path.utf8("xyz")) })
}

## Windows UTF-16 option text follows the same parsing path.
expect {
	parsed = Parser.parse_arg(Path.windows("--alpha=42"))

	parsed == Long({ name: "alpha", value: Ok(Path.utf8("42")) })
}

## A long option preserves an attached non-UTF-8 Unix value.
expect {
	raw_value = [0xFF, 0x80]
	arg = Path.from_raw(UnixBytes(Str.to_utf8("--file=").concat(raw_value)))

	Parser.parse_arg(arg)
		== Long({ name: "file", value: Ok(Path.from_raw(UnixBytes(raw_value))) })
}

## A long option preserves an attached unpaired Windows UTF-16 value.
expect {
	raw_value = [0xD800]
	prefix = [0x002D, 0x002D, 0x0066, 0x0069, 0x006C, 0x0065, 0x003D]
	arg = Path.from_raw(WindowsU16s(prefix.concat(raw_value)))

	Parser.parse_arg(arg)
		== Long({ name: "file", value: Ok(Path.from_raw(WindowsU16s(raw_value))) })
}

## Plain text parses as a positional parameter.
expect {
	parsed = Parser.parse_arg(Path.utf8("123"))

	parsed == Parameter(Path.utf8("123"))
}

## Parsing stops interpreting options after the double-dash delimiter.
expect {
	parsed = 
		Parser.parse_args(["-a", "123", "--passed", "-bcd", "xyz", "--", "--subject=world"].map(Path.utf8))

	parsed
		== [
			Short("a"),
			Parameter(Path.utf8("123")),
			Long({ name: "passed", value: Err(NoValue) }),
			ShortGroup({ names: ["b", "c", "d"], complete: Complete }),
			Parameter(Path.utf8("xyz")),
			PassedThrough(Path.utf8("--subject=world")),
		]
}
