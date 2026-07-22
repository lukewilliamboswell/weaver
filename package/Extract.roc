import path.Path
import Base exposing [ArgExtractErr, OptionConfig, ParameterConfig]
import Parser exposing [ArgValue, ParsedArg]

Extract := [].{
	ExtractParamValuesParams : {
		args : List(ParsedArg),
		param : ParameterConfig,
	}

	ExtractParamValuesState : {
		action : [GetParam, StopParsing],
		values : List(Path),
		remaining_args : List(ParsedArg),
	}

	ExtractParamValuesOutput : {
		values : List(Path),
		remaining_args : List(ParsedArg),
	}

	extract_param_values : ExtractParamValuesParams -> Try(ExtractParamValuesOutput, ArgExtractErr)
	extract_param_values = |{ args, param }| {
		starting_state = {
			action: GetParam,
			values: [],
			remaining_args: [],
		}

		state_after = Extract.extract_param_loop(args, starting_state, param)?

		Ok({ values: state_after.values, remaining_args: state_after.remaining_args })
	}

	extract_param_loop : List(ParsedArg), ExtractParamValuesState, ParameterConfig -> Try(ExtractParamValuesState, ArgExtractErr)
	extract_param_loop = |args, state, param|
		match args {
			[] => Ok(state)
			[arg, .. as rest] => {
				next_state = 
					match state.action {
						GetParam => Extract.extract_single_param(state, param, arg)
						StopParsing => Ok({ ..state, remaining_args: state.remaining_args.append(arg) })
					}?

				Extract.extract_param_loop(rest, next_state, param)
			}
		}

	extract_single_param : ExtractParamValuesState, ParameterConfig, ParsedArg -> Try(ExtractParamValuesState, ArgExtractErr)
	extract_single_param = |state, param, arg|
		match arg {
			Short(short) => Err(UnrecognizedShortArg(short))

			ShortGroup(group) => {
				name = 
					match group.names {
						[] => ""
						[first, ..] => first
					}

				Err(UnrecognizedShortArg(name))
			}

			Long(long) => Err(UnrecognizedLongArg(long.name))

			Parameter(p) | PassedThrough(p) =>
				match param.plurality {
					Optional | One => Ok({ ..state, action: StopParsing, values: state.values.append(p) })
					Many => Ok({ ..state, values: state.values.append(p) })
				}
			}

	ExtractOptionValuesParams : {
		args : List(ParsedArg),
		option : OptionConfig,
	}

	ExtractOptionValuesOutput : {
		values : List(ArgValue),
		remaining_args : List(ParsedArg),
	}

	ExtractOptionValueWalkerState : {
		action : [FindOption, GetValue],
		values : List(ArgValue),
		remaining_args : List(ParsedArg),
	}

	extract_option_values : ExtractOptionValuesParams -> Try(ExtractOptionValuesOutput, ArgExtractErr)
	extract_option_values = |{ args, option }| {
		starting_state = {
			action: FindOption,
			values: [],
			remaining_args: [],
		}

		state_after = Extract.extract_option_loop(args, starting_state, option)?

		match state_after.action {
			GetValue => Err(NoValueProvidedForOption(option))
			FindOption => Ok({ values: state_after.values, remaining_args: state_after.remaining_args })
		}
	}

	extract_option_loop : List(ParsedArg), ExtractOptionValueWalkerState, OptionConfig -> Try(ExtractOptionValueWalkerState, ArgExtractErr)
	extract_option_loop = |args, state, option|
		match args {
			[] => Ok(state)
			[arg, .. as rest] => {
				next_state = 
					match state.action {
						FindOption => Extract.find_option_for_extraction(state, arg, option)
						GetValue => Extract.get_value_for_extraction(state, arg, option)
					}?

				Extract.extract_option_loop(rest, next_state, option)
			}
		}

	find_option_for_extraction : ExtractOptionValueWalkerState, ParsedArg, OptionConfig -> Try(ExtractOptionValueWalkerState, ArgExtractErr)
	find_option_for_extraction = |state, arg, option|
		match arg {
			Short(short) =>
				if short == option.short {
					if option.expected_value == NothingExpected {
						Ok({ ..state, values: state.values.append(Err(NoValue)) })
					} else {
						Ok({ ..state, action: GetValue })
					}
				} else {
					Ok({ ..state, remaining_args: state.remaining_args.append(arg) })
				}

			ShortGroup(short_group) =>
				Extract.find_options_in_short_group(state, option, short_group)

			Long(long) =>
				if long.name == option.long {
					if option.expected_value == NothingExpected {
						match long.value {
							Ok(_) => Err(OptionDoesNotExpectValue(option))
							Err(NoValue) => Ok({ ..state, values: state.values.append(Err(NoValue)) })
						}
					} else {
						match long.value {
							Ok(val) => Ok({ ..state, values: state.values.append(Ok(val)) })
							Err(NoValue) => Ok({ ..state, action: GetValue })
						}
					}
				} else {
					Ok({ ..state, remaining_args: state.remaining_args.append(arg) })
				}

			Parameter(_) | PassedThrough(_) =>
				Ok({ ..state, remaining_args: state.remaining_args.append(arg) })
			}

	find_options_in_short_group : ExtractOptionValueWalkerState, OptionConfig, { names : List(Str), complete : [Partial, Complete] } -> Try(ExtractOptionValueWalkerState, ArgExtractErr)
	find_options_in_short_group = |state, option, short_group| {
		split = split_short_group(short_group.names, option.short, [])

		match split {
			Err(NotFound) =>
				Ok({ ..state, remaining_args: state.remaining_args.append(ShortGroup(short_group)) })

			Ok({ before, after }) =>
				if option.expected_value == NothingExpected {
					remaining = short_group.names.keep_if(|name| name != option.short)
					values = append_flag_values(short_group.names, option.short, state.values)

					next_remaining_args = 
						if remaining.is_empty() {
							state.remaining_args
						} else {
							state.remaining_args.append(ShortGroup({ names: remaining, complete: short_group.complete }))
						}

					Ok({ ..state, values, remaining_args: next_remaining_args })
				} else if short_group.complete == Partial {
					Err(CannotUsePartialShortGroupAsValue(option, short_group.names))
				} else if after.is_empty() {
					next_remaining_args = 
						if before.is_empty() {
							state.remaining_args
						} else {
							state.remaining_args.append(ShortGroup({ names: before, complete: Partial }))
						}

					Ok({ ..state, action: GetValue, remaining_args: next_remaining_args })
				} else {
					Err(ValueOptionMustBeLastInShortGroup(option, short_group.names))
				}
			}
	}

	get_value_for_extraction : ExtractOptionValueWalkerState, ParsedArg, OptionConfig -> Try(ExtractOptionValueWalkerState, ArgExtractErr)
	get_value_for_extraction = |state, arg, option| {
		value = 
			match arg {
				Short(_) => Err(NoValueProvidedForOption(option))
				ShortGroup({ complete: Complete, .. }) => Err(NoValueProvidedForOption(option))
				ShortGroup({ names, complete: Partial }) => Err(CannotUsePartialShortGroupAsValue(option, names))
				Long(_) => Err(NoValueProvidedForOption(option))
				Parameter(p) | PassedThrough(p) => Ok(p)
			}?

		Ok({ ..state, action: FindOption, values: state.values.append(Ok(value)) })
	}
}

split_short_group : List(Str), Str, List(Str) -> Try({ before : List(Str), after : List(Str) }, [NotFound])
split_short_group = |names, target, before|
	match names {
		[] => Err(NotFound)
		[name, .. as rest] =>
			if name == target {
				Ok({ before, after: rest })
			} else {
				split_short_group(rest, target, before.append(name))
			}
		}

append_flag_values : List(Str), Str, List(ArgValue) -> List(ArgValue)
append_flag_values = |names, target, values|
	match names {
		[] => values
		[name, .. as rest] =>
			if name == target {
				append_flag_values(rest, target, values.append(Err(NoValue)))
			} else {
				append_flag_values(rest, target, values)
			}
		}

test_flag : OptionConfig
test_flag = {
	short: "v",
	long: "verbose",
	help: "Increase verbosity.",
	expected_value: NothingExpected,
	plurality: Many,
}

test_value_option : OptionConfig
test_value_option = {
	short: "a",
	long: "alpha",
	help: "Set alpha.",
	expected_value: ExpectsValue("num"),
	plurality: One,
}

## Every occurrence of a flag in one short group is extracted.
expect {
	out = Extract.extract_option_values({
		args: [ShortGroup({ names: ["v", "v", "v"], complete: Complete })],
		option: test_flag,
	})?

	out.values == [Err(NoValue), Err(NoValue), Err(NoValue)] and out.remaining_args == []
}

## Grouped flags before a value option remain available to their own parser.
expect {
	out = Extract.extract_option_values({
		args: [ShortGroup({ names: ["v", "a"], complete: Complete }), Parameter(Path.utf8("7"))],
		option: test_value_option,
	})?

	out.values == [Ok(Path.utf8("7"))]
		and out.remaining_args == [ShortGroup({ names: ["v"], complete: Partial })]
}

## A value option cannot have more short-option characters after it.
expect {
	group = ["a", "v"]

	Extract.extract_option_values({
		args: [ShortGroup({ names: group, complete: Complete }), Parameter(Path.utf8("7"))],
		option: test_value_option,
	}) == Err(ValueOptionMustBeLastInShortGroup(test_value_option, group))
}

## A value option cannot be recovered from a group another value option consumed.
expect {
	group = ["a"]

	Extract.extract_option_values({
		args: [ShortGroup({ names: group, complete: Partial }), Parameter(Path.utf8("7"))],
		option: test_value_option,
	}) == Err(CannotUsePartialShortGroupAsValue(test_value_option, group))
}

## A short option following a value option is not swallowed as its value.
expect {
	Extract.extract_option_values({
		args: [Short("a"), Short("v")],
		option: test_value_option,
	}) == Err(NoValueProvidedForOption(test_value_option))
}

## A long option following a value option is not swallowed as its value.
expect {
	Extract.extract_option_values({
		args: [Long({ name: "alpha", value: Err(NoValue) }), Long({ name: "verbose", value: Err(NoValue) })],
		option: test_value_option,
	}) == Err(NoValueProvidedForOption(test_value_option))
}

## The delimiter explicitly permits an option-like value.
expect {
	value = Path.utf8("-7")
	out = Extract.extract_option_values({
		args: [Short("a"), PassedThrough(value)],
		option: test_value_option,
	})?

	out.values == [Ok(value)] and out.remaining_args == []
}
