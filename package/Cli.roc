import path.Path
import Base exposing [
	ArgExtractErr,
	ArgParserResult,
	CliConfig,
	CliConfigParams,
	TextStyle,
	map_successfully_parsed,
]
import Builder exposing [CliBuilder]
import ErrorFormatter exposing [format_arg_extract_err]
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
		match remaining_args {
			[] => Ok({})
			[first, ..] => {
				extra_arg_err = 
					match first {
						Parameter(param) => ExtraParamProvided(param)
						Long(long) => UnrecognizedLongArg(long.name)
						Short(short) => UnrecognizedShortArg(short)
						ShortGroup(short_group) => UnrecognizedShortArg(first_or_empty(short_group.names))
					}

				Err(extra_arg_err)
			}
		}

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
			subcommands: HasSubcommands(subcommands),
		}

		{
			config,
			text_style,
			parser: |args|
				map_successfully_parsed(
					parser({ args: parse_args(args), subcommand_path: [name] }),
					|{ data, .. }| data,
				),
		}
	}

	## Assert that a CLI is properly configured, crashing your program if not.
	assert_valid : Try(CliParser(data), CliValidationErr) -> CliParser(data)
	assert_valid = |result|
		match result {
			Ok(cli) => cli
			Err(_err) => {
				crash "Invalid Weaver CLI configuration. Handle the result from Cli.finish to inspect the validation error."
			}
		}

	## Parse arguments using a CLI parser or return a useful message.
	parse_or_display_message : CliParser(data), List(arg), (arg -> [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]) -> Try(data, Str)
	parse_or_display_message = |{ config, parser, text_style }, external_args, to_raw_arg| {
		args = 
			external_args
				.map(to_raw_arg)
				.map(Path.from_raw)

		match parser(args) {
			SuccessfullyParsed(data) => Ok(data)
			ShowHelp({ subcommand_path }) => Err(help_text(config, subcommand_path, text_style))
			ShowVersion => Err(config.version)
			IncorrectUsage(err, { subcommand_path }) => {
				usage_str = usage_help(config, subcommand_path, text_style)
				incorrect_usage_str = "Error: ${format_arg_extract_err(err)}\n\n${usage_str}"

				Err(incorrect_usage_str)
			}
		}
	}
}

first_or_empty : List(Str) -> Str
first_or_empty = |values|
	match values {
		[] => ""
		[first, ..] => first
	}
