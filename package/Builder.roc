import path.Path
import Base exposing [
	ArgExtractErr,
	ArgParser,
	ArgParserResult,
	ArgParserState,
	OptionConfig,
	ParameterConfig,
	SubcommandConfig,
	help_option,
	map_successfully_parsed,
	on_successful_arg_parse,
	version_option,
]
import Parser exposing [ParsedArg]

Builder(data, from_action, to_action) := {
	parser : ArgParser(data),
	options : List(OptionConfig),
	parameters : List(ParameterConfig),
	subcommands : Dict(Str, SubcommandConfig),
}.{
	GetOptionsAction : { get_options : {} }
	GetParamsAction : { get_params : {} }
	StopCollectingAction : []

	CliBuilder(data, from_action, to_action) : Builder(data, from_action, to_action)

	from_arg_parser : (List(ParsedArg) -> Try({ data : data, remaining_args : List(ParsedArg) }, ArgExtractErr)) -> CliBuilder(data, from_action, to_action)
	from_arg_parser = |parser| {
		new_parser = |{ args, subcommand_path }|
			match parser(args) {
				Ok({ data, remaining_args }) =>
					ArgParserResult.SuccessfullyParsed({ data, remaining_args, subcommand_path })

				Err(err) =>
					ArgParserResult.IncorrectUsage(err, { subcommand_path: subcommand_path })
				}

		{
			parser: new_parser,
			options: [],
			parameters: [],
			subcommands: Dict.empty(),
		}
	}

	from_full_parser : ArgParser(data) -> CliBuilder(data, from_action, to_action)
	from_full_parser = |parser| {
		parser,
		options: [],
		parameters: [],
		subcommands: Dict.empty(),
	}

	add_option : CliBuilder(state, from_action, to_action), OptionConfig -> CliBuilder(state, from_action, to_action)
	add_option = |{ parser, options, parameters, subcommands }, new_option| {
		parser,
		options: options.append(new_option),
		parameters,
		subcommands,
	}

	add_parameter : CliBuilder(state, from_action, to_action), ParameterConfig -> CliBuilder(state, from_action, to_action)
	add_parameter = |{ parser, options, parameters, subcommands }, new_parameter| {
		parser,
		options,
		parameters: parameters.append(new_parameter),
		subcommands,
	}

	add_subcommands : CliBuilder(state, from_action, to_action), Dict(Str, SubcommandConfig) -> CliBuilder(state, from_action, to_action)
	add_subcommands = |{ parser, options, parameters, subcommands }, new_subcommands| {
		parser,
		options,
		parameters,
		subcommands: Dict.insert_all(subcommands, new_subcommands),
	}

	set_parser : CliBuilder(state, from_action, to_action), ArgParser(next_state) -> CliBuilder(next_state, from_action, to_action)
	set_parser = |{ options, parameters, subcommands, parser: _old_parser }, next_parser| {
		options,
		parameters,
		subcommands,
		parser: next_parser,
	}

	update_parser : CliBuilder(state, from_action, to_action), ({ data : state, remaining_args : List(ParsedArg) } -> Try({ data : next_state, remaining_args : List(ParsedArg) }, ArgExtractErr)) -> CliBuilder(next_state, from_action, to_action)
	update_parser = |{ parser, options, parameters, subcommands }, updater| {
		new_parser = 
			on_successful_arg_parse(
				parser,
				|{ data, remaining_args, subcommand_path }|
					match updater({ data, remaining_args }) {
						Err(err) => ArgParserResult.IncorrectUsage(err, { subcommand_path: subcommand_path })
						Ok({ data: updated_data, remaining_args: rest_of_args }) =>
							ArgParserResult.SuccessfullyParsed({ data: updated_data, remaining_args: rest_of_args, subcommand_path })
						},
			)

		Builder.set_parser({ parser, options, parameters, subcommands }, new_parser)
	}

	bind_parser : CliBuilder(state, from_action, to_action), (ArgParserState(state) -> ArgParserResult(ArgParserState(next_state))) -> CliBuilder(next_state, from_action, to_action)
	bind_parser = |{ parser, options, parameters, subcommands }, updater| {
		new_parser : ArgParser(next_state)
		new_parser = 
			on_successful_arg_parse(
				parser,
				|{ data, remaining_args, subcommand_path }|
					updater({ data, remaining_args, subcommand_path }),
			)

		Builder.set_parser({ parser, options, parameters, subcommands }, new_parser)
	}

	into_parts :
		CliBuilder(state, from_action, to_action) -> {
			parser : ArgParser(state),
			options : List(OptionConfig),
			parameters : List(ParameterConfig),
			subcommands : Dict(Str, SubcommandConfig),
		}
	into_parts = |{ parser, options, parameters, subcommands }| {
		parser,
		options,
		parameters,
		subcommands,
	}

	map : CliBuilder(a, from_action, to_action), (a -> b) -> CliBuilder(b, from_action, to_action)
	map = |{ parser, options, parameters, subcommands }, mapper| {
		combined_parser = |input|
			map_successfully_parsed(
				parser(input),
				|{ data, remaining_args, subcommand_path }|
					{ data: mapper(data), remaining_args, subcommand_path },
			)

		{
			parser: combined_parser,
			options,
			parameters,
			subcommands,
		}
	}

	combine : CliBuilder(a, action1, action2), CliBuilder(b, action2, action3), (a, b -> c) -> CliBuilder(c, action1, action3)
	combine = |{ parser: left_parser, options: left_options, parameters: left_parameters, subcommands: left_subcommands }, { parser: right_parser, options: right_options, parameters: right_parameters, subcommands: right_subcommands }, combiner| {
		combined_parser = |input|
			match left_parser(input) {
				ShowVersion => ArgParserResult.ShowVersion
				ShowHelp(sp) => ArgParserResult.ShowHelp(sp)
				IncorrectUsage(arg_extract_err, sp) => ArgParserResult.IncorrectUsage(arg_extract_err, sp)
				SuccessfullyParsed({ data, remaining_args, subcommand_path }) =>
					match right_parser({ args: remaining_args, subcommand_path }) {
						ShowVersion => ArgParserResult.ShowVersion
						ShowHelp(sp) => ArgParserResult.ShowHelp(sp)
						IncorrectUsage(arg_extract_err, sp) => ArgParserResult.IncorrectUsage(arg_extract_err, sp)
						SuccessfullyParsed({ data: data2, remaining_args: rest_of_args, subcommand_path: next_sp }) =>
							ArgParserResult.SuccessfullyParsed({ data: combiner(data, data2), remaining_args: rest_of_args, subcommand_path: next_sp })
						}
				}

		{
			parser: combined_parser,
			options: left_options.concat(right_options),
			parameters: left_parameters.concat(right_parameters),
			subcommands: Dict.insert_all(left_subcommands, right_subcommands),
		}
	}

	flag_was_passed : OptionConfig, List(ParsedArg) -> Bool
	flag_was_passed = |option, args|
		args.any(
			|arg|
				match arg {
					Short(short) => short == option.short
					ShortGroup(sg) => sg.names.any(|n| n == option.short)
					Long(long) => long.name == option.long
					Parameter(_) => False
				},
		)

	check_for_help_and_version : CliBuilder(state, from_action, to_action) -> CliBuilder(state, from_action, to_action)
	check_for_help_and_version = |{ parser, options, parameters, subcommands }| {
		new_parser = |{ args, subcommand_path }|
			match parser({ args, subcommand_path }) {
				ShowHelp(sp) => ArgParserResult.ShowHelp(sp)
				ShowVersion => ArgParserResult.ShowVersion
				other =>
					if Builder.flag_was_passed(help_option, args) {
						ArgParserResult.ShowHelp({ subcommand_path: subcommand_path })
					} else if Builder.flag_was_passed(version_option, args) {
						ArgParserResult.ShowVersion
					} else {
						other
					}
				}

		{
			options: options.concat([help_option, version_option]),
			parameters,
			subcommands,
			parser: new_parser,
		}
	}
}

## Mapping a builder transforms parsed data without consuming extra arguments.
expect {
	{ parser, .. } = 
		Builder.into_parts(
			Builder.map(
				Builder.from_arg_parser(|args| Ok({ data: args.len(), remaining_args: [] })),
				|value| Count(value),
			),
		)

	out = parser({ args: [Parameter(Path.utf8("123"))], subcommand_path: [] })

	out
		== ArgParserResult.SuccessfullyParsed({
			data: Count(1),
			remaining_args: [],
			subcommand_path: [],
		})
}

## Raw parameter text does not trigger the built-in help flag.
expect {
	args = [Parameter(Path.utf8("-h"))]

	!(Builder.flag_was_passed(help_option, args))
}

## The short help option triggers the built-in help flag.
expect {
	args = [Short("h")]

	Builder.flag_was_passed(help_option, args)
}

## The long help option triggers the built-in help flag.
expect {
	args = [Long({ name: "help", value: Err(NoValue) })]

	Builder.flag_was_passed(help_option, args)
}

## A value attached to the long help option still triggers help handling.
expect {
	args = [Long({ name: "help", value: Ok(Path.utf8("123")) })]

	Builder.flag_was_passed(help_option, args)
}
