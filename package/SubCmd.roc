import Arg exposing [Arg]
import Base exposing [
	ArgParser,
	ArgParserResult,
	ArgParserState,
	SubcommandConfig,
	SubcommandsConfig,
	on_successful_arg_parse,
]
import Builder exposing [CliBuilder, GetOptionsAction, GetParamsAction]

SubCmd := [].{
	SubcommandParserConfig(sub_state) : {
		name : Str,
		parser : ArgParser(sub_state),
		config : SubcommandConfig,
	}

	## Create an empty subcommand.
	empty : { name : Str, description : Str, value : common_state } -> SubcommandParserConfig(common_state)
	empty = |{ name, description, value }| {
		{ options, parameters, subcommands, parser } = 
			Builder.into_parts(
				Builder.check_for_help_and_version(
					Builder.from_arg_parser(|args| Ok({ data: value, remaining_args: args })),
				),
			)

		config = {
			description,
			options,
			parameters,
			subcommands: SubcommandsConfig.HasSubcommands(subcommands),
		}

		{ name, config, parser }
	}

	## Bundle a CLI builder into a subcommand.
	finish : CliBuilder(state, from_action, to_action), { name : Str, description : Str, mapper : state -> common_state } -> SubcommandParserConfig(common_state)
	finish = |builder, { name, description, mapper }| {
		{ options, parameters, subcommands, parser } = 
			Builder.into_parts(
				Builder.update_parser(
					Builder.check_for_help_and_version(builder),
					|{ data, remaining_args }| Ok({ data: mapper(data), remaining_args }),
				),
			)

		config = {
			description,
			options,
			parameters,
			subcommands: SubcommandsConfig.HasSubcommands(subcommands),
		}

		{ name, config, parser }
	}

	get_first_arg_to_check_for_subcommand_call :
		ArgParserState(_), List(SubcommandParserConfig(sub_state)), (Try(SubcommandParserConfig(sub_state), [NotFound]) -> ArgParserResult(ArgParserState(state))) -> ArgParserResult(ArgParserState(state))
	get_first_arg_to_check_for_subcommand_call = |{ remaining_args, subcommand_path, .. }, subcommand_parsers, callback| {
		find_subcommand = |param|
			match param {
				Err(NoValue) => Err(NotFound)
				Ok(arg) =>
					match Arg.to_str(arg) {
						Err(InvalidUtf8) => Err(NotFound)
						Ok(name) => find_subcommand_by_name(subcommand_parsers, name)
					}
				}

		match remaining_args.first() {
			Err(ListWasEmpty) => callback(find_subcommand(Err(NoValue)))
			Ok(first_arg) =>
				match first_arg {
					Short(short) => ArgParserResult.IncorrectUsage(UnrecognizedShortArg(short), { subcommand_path: subcommand_path })
					Long(long) => ArgParserResult.IncorrectUsage(UnrecognizedLongArg(long.name), { subcommand_path: subcommand_path })
					ShortGroup(sg) => ArgParserResult.IncorrectUsage(UnrecognizedShortArg(first_or_empty(sg.names)), { subcommand_path: subcommand_path })
					Parameter(p) => callback(find_subcommand(Ok(p)))
				}
			}
	}

	## Use previously defined subcommands as optional data in a parent CLI.
	optional : List(SubcommandParserConfig(sub_state)) -> CliBuilder(Try(sub_state, [NoSubcommand]), GetOptionsAction, GetParamsAction)
	optional = |subcommand_configs| {
		subcommands = 
			Dict.from_list(subcommand_configs.map(|subcommand| (subcommand.name, subcommand.config)))

		full_parser = |{ args, subcommand_path }|
			SubCmd.get_first_arg_to_check_for_subcommand_call(
				{ data: {}, remaining_args: args, subcommand_path },
				subcommand_configs,
				|subcommand_found|
					match subcommand_found {
						Err(NotFound) =>
							ArgParserResult.SuccessfullyParsed({ data: Err(NoSubcommand), remaining_args: args, subcommand_path })

						Ok(subcommand) => {
							sub_parser = 
								on_successful_arg_parse(
									subcommand.parser,
									|{ data: sub_data, remaining_args: sub_remaining_args, subcommand_path: sub_subcommand_path }|
										ArgParserResult.SuccessfullyParsed({ data: Ok(sub_data), remaining_args: sub_remaining_args, subcommand_path: sub_subcommand_path }),
								)

							sub_parser({
								args: args.drop_first(1),
								subcommand_path: subcommand_path.append(subcommand.name),
							})
						}
					},
			)

		Builder.add_subcommands(Builder.from_full_parser(full_parser), subcommands)
	}

	## Use previously defined subcommands as required data in a parent CLI.
	required : List(SubcommandParserConfig(sub_data)) -> CliBuilder(sub_data, GetOptionsAction, GetParamsAction)
	required = |subcommand_configs| {
		subcommands = 
			Dict.from_list(subcommand_configs.map(|subcommand| (subcommand.name, subcommand.config)))

		full_parser = |{ args, subcommand_path }|
			SubCmd.get_first_arg_to_check_for_subcommand_call(
				{ data: {}, remaining_args: args, subcommand_path },
				subcommand_configs,
				|subcommand_found|
					match subcommand_found {
						Err(NotFound) =>
							ArgParserResult.IncorrectUsage(NoSubcommandCalled, { subcommand_path: subcommand_path })

						Ok(subcommand) => {
							sub_parser = 
								on_successful_arg_parse(
									subcommand.parser,
									|{ data: sub_data, remaining_args: sub_remaining_args, subcommand_path: sub_subcommand_path }|
										ArgParserResult.SuccessfullyParsed({ data: sub_data, remaining_args: sub_remaining_args, subcommand_path: sub_subcommand_path }),
								)

							sub_parser({
								args: args.drop_first(1),
								subcommand_path: subcommand_path.append(subcommand.name),
							})
						}
					},
			)

		Builder.add_subcommands(Builder.from_full_parser(full_parser), subcommands)
	}
}

find_subcommand_by_name : List(SubCmd.SubcommandParserConfig(sub_state)), Str -> Try(SubCmd.SubcommandParserConfig(sub_state), [NotFound])
find_subcommand_by_name = |subcommands, target|
	match subcommands {
		[] => Err(NotFound)
		[subcommand, .. as rest] =>
			if subcommand.name == target {
				Ok(subcommand)
			} else {
				find_subcommand_by_name(rest, target)
			}
		}

first_or_empty : List(Str) -> Str
first_or_empty = |values|
	match values {
		[] => ""
		[first, ..] => first
	}
