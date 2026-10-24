import path.Path
import Base exposing [
	ArgExtractErr,
	ArgParserResult,
	CliConfig,
	CliConfigParams,
	OptionConfig,
	SubcommandConfig,
	SubcommandsConfig,
	TextStyle,
	map_successfully_parsed,
]
import Builder exposing [CliBuilder]
import Extract
import ErrorFormatter exposing [render_arg_extract_err]
import Help exposing [help_text, usage_help]
import Parser exposing [ParsedArg, parse_args]
import Validate exposing [CliValidationErr, validate_cli]

## Weave together a CLI parser using current Roc record-builder syntax.
Cli := [].{

	## A parser that interprets command line arguments and returns typed data.
	CliParser(state) : {
		config : CliConfig,
		parser : List(Path) -> ArgParserResult(state),
		text_style : TextStyle,
	}

	## Map over the parsed value of a Weaver field.
	map : CliBuilder(a, from_action, to_action), (a -> b) -> CliBuilder(b, from_action, to_action)
	map = |builder, mapper|
		Builder.map(builder, mapper)

	## Combine two CLI builders. This powers current Roc record-builder syntax:
	## `{ name: Param.str(...), verbose: Opt.flag(...) }.Cli`.
	map2 : CliBuilder(a, action1, action2), CliBuilder(b, action2, action3), (a, b -> c) -> CliBuilder(c, action1, action3)
	map2 = |left, right, combiner|
		Builder.combine(left, right, combiner)

	## Alias for `map2` for code that wants a descriptive function name.
	weave : CliBuilder(a, action1, action2), CliBuilder(b, action2, action3), (a, b -> c) -> CliBuilder(c, action1, action3)
	weave = |left, right, combiner|
		Cli.map2(left, right, combiner)

	## Fail the parsing process if any arguments are left over after parsing.
	ensure_all_args_were_parsed : List(ParsedArg) -> Try({}, ArgExtractErr)
	ensure_all_args_were_parsed = |remaining_args|
		Extract.ensure_no_remaining_args(remaining_args)

	## Bundle a CLI builder into a parser, ensuring its configuration is valid.
	finish : CliBuilder(data, from_action, to_action), CliConfigParams -> Try(CliParser(data), CliValidationErr)
	finish = |builder, params| {
		cli = Cli.finish_without_validating(builder, params)
		validate_cli(cli.config)?

		Ok(cli)
	}

	## Bundle a CLI builder into a parser without validating its configuration.
	finish_without_validating : CliBuilder(data, from_action, to_action), CliConfigParams -> CliParser(data)
	finish_without_validating = |builder, { name, authors, version, description, text_style }| {
		{ options, parameters, subcommands, parser } =
			Builder.into_parts(
				Builder.update_parser(
					Builder.check_for_help_and_version(builder),
					|data| {
						Cli.ensure_all_args_were_parsed(data.remaining_args)?

						Ok(data)
					},
				),
			)

		config = {
			name,
			authors,
			version,
			description,
			options,
			parameters,
			subcommands,
		}

		{
			config,
			text_style,
			parser: |args| {
				parsed_args = parse_args(args)
				raw_result = parser({ args: parsed_args, subcommand_path: [name] })
				parser_result =
					match raw_result {
						IncorrectUsage(MissingOption(_), _) =>
							match find_unrecognized_option(config, parsed_args) {
								Ok({}) => raw_result
								Err((err, subcommand_path)) => ArgParserResult.IncorrectUsage(err, { subcommand_path: subcommand_path })
							}

						_other => raw_result
					}

				map_successfully_parsed(parser_result, |{ data, .. }| data)
			},
		}
	}

	## Assert that a CLI is properly configured, crashing your program if not.
	## Handle `Cli.finish` directly to render its validation error.
	assert_valid : Try(CliParser(data), CliValidationErr) -> CliParser(data)
	assert_valid = |result|
		match result {
			Ok(cli) => cli
			Err(_err) => {
				crash "Invalid Weaver CLI configuration. Handle the result from Cli.finish with ErrorFormatter.render_cli_validation_err."
			}
		}

	## Parse arguments, or return a typed help, version, or usage message.
	parse_or_display_message : CliParser(data), List(arg), (arg -> [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]) -> Try(data, [Help(Str), Version(Str), InvalidUsage(Str)])
	parse_or_display_message = |{ config, parser, text_style }, external_args, to_raw_arg| {
		args =
			external_args
				.map(to_raw_arg)
				.map(Path.from_raw)

		match parser(args) {
			SuccessfullyParsed(data) => Ok(data)
			ShowHelp({ subcommand_path }) => Err(Help(help_text(config, subcommand_path, text_style)))
			ShowVersion => Err(Version(config.version))
			IncorrectUsage(err, { subcommand_path }) => {
				usage_str = usage_help(config, subcommand_path, text_style)
				command = Str.join_with(subcommand_path, " ")
				incorrect_usage_str = render_arg_extract_err(err, { command, usage: usage_str }, text_style)

				Err(InvalidUsage(incorrect_usage_str))
			}
		}
	}
}

## Find an option that is not declared by the command it was given to, and
## the path of that command. Arguments after a subcommand's name are given to
## that subcommand, so each one is checked against its own command only.
find_unrecognized_option : CliConfig, List(ParsedArg) -> Try({}, (ArgExtractErr, List(Str)))
find_unrecognized_option = |config, args| {
	find_unrecognized_option_in_command(args, config.options, config.subcommands, [config.name])
}

find_unrecognized_option_in_command : List(ParsedArg), List(OptionConfig), SubcommandsConfig, List(Str) -> Try({}, (ArgExtractErr, List(Str)))
find_unrecognized_option_in_command = |args, options, subcommands, subcommand_path| {
	commands =
		match subcommands {
			NoSubcommands => []
			HasSubcommands(group) => group.commands
		}
	boundary = Extract.find_subcommand_boundary(args, options, commands.map(|(name, _)| name))
	own_args =
		match boundary {
			Ok(index) => args.take_first(index)
			Err(NotFound) => args
		}

	match find_unrecognized_option_in_args(own_args, options) {
		Err(err) => Err((err, subcommand_path))
		Ok({}) =>
			match boundary {
				Err(NotFound) => Ok({})
				Ok(index) =>
					match args.get(index) {
						Ok(Parameter(name_arg)) =>
							match find_command_by_name(commands, Path.to_str(name_arg) ?? "") {
								Ok((name, command)) =>
									find_unrecognized_option_in_command(
										args.drop_first(index + 1),
										command.options,
										command.subcommands,
										subcommand_path.append(name),
									)

								Err(NotFound) => Ok({})
							}

						_other => Ok({})
					}
			}
	}
}

find_command_by_name : List((Str, SubcommandConfig)), Str -> Try((Str, SubcommandConfig), [NotFound])
find_command_by_name = |commands, target|
	match commands {
		[] => Err(NotFound)
		[(name, command), .. as rest] =>
			if name == target {
				Ok((name, command))
			} else {
				find_command_by_name(rest, target)
			}
	}

option_is_known : List(OptionConfig), (OptionConfig -> Bool) -> Bool
option_is_known = |options, predicate|
	options.any(predicate)

find_unrecognized_option_in_args : List(ParsedArg), List(OptionConfig) -> Try({}, ArgExtractErr)
find_unrecognized_option_in_args = |args, options|
	match args {
		[] => Ok({})
		[first, .. as rest] => {
			match first {
				Short(name) =>
					if option_is_known(options, |option| Parser.names_option(name, option.short)) {
						find_unrecognized_option_in_args(rest, options)
					} else {
						Err(UnrecognizedShortArg(name))
					}

				ShortGroup({ names, .. }) => {
					find_unrecognized_short_name(names, options)?
					find_unrecognized_option_in_args(rest, options)
				}

				Long({ name, .. }) =>
					if option_is_known(options, |option| Parser.names_option(name, option.long)) {
						find_unrecognized_option_in_args(rest, options)
					} else {
						Err(UnrecognizedLongArg(name))
					}

				Parameter(_) | PassedThrough(_) =>
					find_unrecognized_option_in_args(rest, options)
			}
		}
	}

find_unrecognized_short_name : List(Str), List(OptionConfig) -> Try({}, ArgExtractErr)
find_unrecognized_short_name = |names, options|
	match names {
		[] => Ok({})
		[name, .. as rest] =>
			if option_is_known(options, |option| Parser.names_option(name, option.short)) {
				find_unrecognized_short_name(rest, options)
			} else {
				Err(UnrecognizedShortArg(name))
			}
	}
