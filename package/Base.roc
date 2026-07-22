import path.Path
import Parser exposing [ParsedArg]

Base := [].{

	## The result of attempting to parse args into config data.
	ArgParserResult(a) := [
		ShowHelp({ subcommand_path : List(Str) }),
		ShowVersion,
		IncorrectUsage(ArgExtractErr, { subcommand_path : List(Str) }),
		SuccessfullyParsed(a),
	].{
		is_eq : _
	}

	## The parameters that an `ArgParser` takes to extract data from args.
	ArgParserParams : { args : List(ParsedArg), subcommand_path : List(Str) }

	## The intermediate state that an `ArgParser` passes between steps.
	ArgParserState(a) : { data : a, remaining_args : List(ParsedArg), subcommand_path : List(Str) }

	## A function that extracts configuration data from parsed arguments.
	ArgParser(a) : ArgParserParams -> ArgParserResult(ArgParserState(a))

	## A bind operation for `ArgParserState`.
	on_successful_arg_parse : ArgParser(a), (ArgParserState(a) -> ArgParserResult(ArgParserState(b))) -> ArgParser(b)
	on_successful_arg_parse = |result, mapper| {
		|input|
			match result(input) {
				ShowVersion => ArgParserResult.ShowVersion
				ShowHelp({ subcommand_path }) => ArgParserResult.ShowHelp({ subcommand_path: subcommand_path })
				IncorrectUsage(arg_extract_err, { subcommand_path }) => ArgParserResult.IncorrectUsage(arg_extract_err, { subcommand_path: subcommand_path })
				SuccessfullyParsed({ data, remaining_args, subcommand_path }) =>
					mapper({ data, remaining_args, subcommand_path })
				}
	}

	## Maps successfully parsed data in an `ArgParserResult`.
	map_successfully_parsed : ArgParserResult(a), (a -> b) -> ArgParserResult(b)
	map_successfully_parsed = |result, mapper|
		match result {
			ShowVersion => ArgParserResult.ShowVersion
			ShowHelp({ subcommand_path }) => ArgParserResult.ShowHelp({ subcommand_path: subcommand_path })
			IncorrectUsage(arg_extract_err, { subcommand_path }) => ArgParserResult.IncorrectUsage(arg_extract_err, { subcommand_path: subcommand_path })
			SuccessfullyParsed(parsed) => ArgParserResult.SuccessfullyParsed(mapper(parsed))
		}

	## Errors that can occur while extracting values from command line arguments.
	ArgExtractErr : [
		NoSubcommandCalled,
		MissingOption(OptionConfig),
		OptionCanOnlyBeSetOnce(OptionConfig),
		NoValueProvidedForOption(OptionConfig),
		OptionDoesNotExpectValue(OptionConfig),
		CannotUsePartialShortGroupAsValue(OptionConfig, List(Str)),
		ValueOptionMustBeLastInShortGroup(OptionConfig, List(Str)),
		InvalidOptionValue(InvalidValue, OptionConfig),
		InvalidParamValue(InvalidValue, ParameterConfig),
		MissingParam(ParameterConfig),
		UnrecognizedSubcommand(Path),
		UnrecognizedShortArg(Str),
		UnrecognizedLongArg(Str),
		ExtraParamProvided(Path),
	]

	str_type_name : Str
	str_type_name = "str"

	num_type_name : Str
	num_type_name = "num"

	## Convert an OS-aware argument to bytes, using big-endian code units on Windows.
	arg_to_bytes : Path -> List(U8)
	arg_to_bytes = |arg|
		match Path.to_raw(arg) {
			Utf8(str) => Str.to_utf8(str)
			UnixBytes(bytes) => bytes
			WindowsU16s(code_units) =>
				code_units.fold(
					[],
					|bytes, code_unit| {
						upper = U64.to_u8_wrap(U16.to_u64(code_unit / 256))
						lower = U64.to_u8_wrap(U16.to_u64(code_unit % 256))

						bytes.append(upper).append(lower)
					},
				)
			}

	## Whether help text should have fancy styling.
	TextStyle : [Color, Plain]

	## The type of value that an option expects to parse.
	ExpectedValue : [ExpectsValue(Str), NothingExpected]

	## How many values an option/parameter can take.
	Plurality : [Optional, One, Many]

	## The two built-in flags that we parse automatically.
	SpecialFlags : { help : Bool, version : Bool }

	InvalidValue : [InvalidNumStr, InvalidValue(Str), InvalidUtf8]

	DefaultValue(a) : [NoDefault, Value(a), Generate({} -> a)]

	## A parser that extracts an argument value.
	ValueParser(a) : Path -> Try(a, InvalidValue)

	OptionConfigBaseParams : { short : Str, long : Str, help : Str }

	DefaultableOptionConfigBaseParams(a) : {
		short : Str,
		long : Str,
		help : Str,
		default : DefaultValue(a),
	}

	## Options for creating an option with a custom parser.
	OptionConfigParams(a) : {
		short : Str,
		long : Str,
		help : Str,
		type : Str,
		parser : ValueParser(a),
	}

	## Options for creating an option with a custom parser and default.
	DefaultableOptionConfigParams(a) : {
		short : Str,
		long : Str,
		help : Str,
		type : Str,
		parser : ValueParser(a),
		default : DefaultValue(a),
	}

	## Metadata for options in our CLI building system.
	OptionConfig : {
		expected_value : ExpectedValue,
		plurality : Plurality,
		required : Bool,
		short : Str,
		long : Str,
		help : Str,
	}

	## Metadata for the `-h/--help` option that we parse automatically.
	help_option : OptionConfig
	help_option = {
		short: "h",
		long: "help",
		help: "Show this help page.",
		expected_value: NothingExpected,
		plurality: Optional,
		required: False,
	}

	## Metadata for the `-V/--version` option that we parse automatically.
	version_option : OptionConfig
	version_option = {
		short: "V",
		long: "version",
		help: "Show the version.",
		expected_value: NothingExpected,
		plurality: Optional,
		required: False,
	}

	ParameterConfigBaseParams : { name : Str, help : Str }

	DefaultableParameterConfigBaseParams(a) : { name : Str, help : Str, default : DefaultValue(a) }

	## Options for creating a parameter with a custom parser.
	ParameterConfigParams(a) : {
		name : Str,
		help : Str,
		type : Str,
		parser : ValueParser(a),
	}

	## Options for creating a parameter with a custom parser and default.
	DefaultableParameterConfigParams(a) : {
		name : Str,
		help : Str,
		type : Str,
		parser : ValueParser(a),
		default : DefaultValue(a),
	}

	## Metadata for parameters in our CLI building system.
	ParameterConfig : {
		name : Str,
		help : Str,
		type : Str,
		plurality : Plurality,
		required : Bool,
	}

	## Options for bundling a CLI.
	CliConfigParams : {
		name : Str,
		authors : List(Str),
		version : Str,
		description : Str,
		text_style : TextStyle,
	}

	## Metadata for a root-level CLI.
	CliConfig : {
		name : Str,
		authors : List(Str),
		version : Str,
		description : Str,
		subcommands : SubcommandsConfig,
		options : List(OptionConfig),
		parameters : List(ParameterConfig),
	}

	## Options for bundling a subcommand.
	SubcommandConfigParams : { name : Str, description : Str }

	## Metadata for a subcommand.
	SubcommandConfig : {
		description : Str,
		options : List(OptionConfig),
		parameters : List(ParameterConfig),
		subcommands : SubcommandsConfig,
	}

	## Subcommands retain declaration order and duplicate names for validation.
	SubcommandsConfig := [
		NoSubcommands,
		HasSubcommands(
			{
				commands : List((Str, SubcommandConfig)),
				required : Bool,
			},
		),
	]
}
