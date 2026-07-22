import Base exposing [ArgExtractErr, ExpectedValue, num_type_name, str_type_name]
import Validate exposing [CliValidationErr]
import path.Path

ErrorFormatter := [].{

	## Render `ArgExtractErr` errors as readable messages.
	format_arg_extract_err : ArgExtractErr -> Str
	format_arg_extract_err = |err|
		match err {
			NoSubcommandCalled =>
				"A subcommand must be called."

			MissingOption(option) =>
				"Required option ${option_display_name(option)} is missing."

			OptionCanOnlyBeSetOnce(option) =>
				"Option ${option_display_name(option)} can only be set once."

			NoValueProvidedForOption(option) =>
				"Option ${option_display_name(option)} expects a ${option_type_name(option)}."

			OptionDoesNotExpectValue(option) =>
				"Option ${option_display_name(option)} does not expect a value."

			CannotUsePartialShortGroupAsValue(option, partial_group) => {
				rendered_group = "-${Str.join_with(partial_group, "")}"

				"The short option group ${rendered_group} was partially consumed and cannot be used as a value for ${option_display_name(option)}."
			}

			ValueOptionMustBeLastInShortGroup(option, group) => {
				rendered_group = "-${Str.join_with(group, "")}"

				"Option ${option_display_name(option)} must be last in the short option group ${rendered_group}."
			}

			InvalidOptionValue(value_err, option) =>
				match value_err {
					InvalidNumStr =>
						"The value provided to ${option_display_name(option)} was not a valid number."

					InvalidValue(reason) =>
						"The value provided to ${option_display_name(option)} was not a valid ${option_type_name(option)}: ${reason}"

					InvalidUtf8 =>
						"The value provided to ${option_display_name(option)} was not valid UTF-8."
					}

			InvalidParamValue(value_err, param) =>
				match value_err {
					InvalidNumStr =>
						"The value provided to the '${param.name}' parameter was not a valid number."

					InvalidValue(reason) =>
						"The value provided to the '${param.name}' parameter was not a valid ${full_type_name(param.type)}: ${reason}."

					InvalidUtf8 =>
						"The value provided to the '${param.name}' parameter was not valid UTF-8."
					}

			MissingParam(parameter) =>
				"The '${parameter.name}' parameter did not receive a value."

			UnrecognizedShortArg(short) =>
				"The argument -${short} was not recognized."

			UnrecognizedLongArg(long) =>
				"The argument --${long} was not recognized."

			ExtraParamProvided(param) =>
				"The parameter ${Str.inspect(Path.display(param))} was not expected."
			}

	## Render `CliValidationErr` errors as readable messages.
	format_cli_validation_err : CliValidationErr -> Str
	format_cli_validation_err = |err| {
		value_at_subcommand_name = |{ name, subcommand_path }| {
			subcommand_path_suffix = 
				if subcommand_path.len() <= 1 {
					""
				} else {
					" for command '${Str.join_with(subcommand_path, " ")}'"
				}

			"${name}${subcommand_path_suffix}"
		}

		option_at_subcommand_name = |{ option, subcommand_path }|
			value_at_subcommand_name({ name: "option '${option_display_name(option)}'", subcommand_path })

		param_at_subcommand_name = |{ name, subcommand_path }|
			value_at_subcommand_name({ name: "parameter '${name}'", subcommand_path })

		match err {
			OverlappingOptionNames({ left: option1, right: option2 }) =>
				"The ${option_at_subcommand_name(option1)} overlaps with the ${option_at_subcommand_name(option2)}."

			OverlappingParameterNames({ first, second, subcommand_path }) =>
				"The ${param_at_subcommand_name({ name: first, subcommand_path })} overlaps with the ${param_at_subcommand_name({ name: second, subcommand_path })}."

			InvalidShortFlagName({ name, subcommand_path }) => {
				value_name = "option '-${name}'"
				"The ${value_at_subcommand_name({ name: value_name, subcommand_path })} is not a single character."
			}

			InvalidLongFlagName({ name, subcommand_path }) => {
				value_name = "option '--${name}'"
				"The ${value_at_subcommand_name({ name: value_name, subcommand_path })} is not kebab-case and at least two characters."
			}

			InvalidCommandName({ name, subcommand_path }) => {
				value_name = "command '${name}'"
				"The ${value_at_subcommand_name({ name: value_name, subcommand_path })} is not kebab-case."
			}

			InvalidParameterName({ name, subcommand_path }) => {
				value_name = "parameter '${name}'"
				"The ${value_at_subcommand_name({ name: value_name, subcommand_path })} is not kebab-case."
			}

			OptionMustHaveShortOrLongName({ subcommand_path }) =>
				"An ${value_at_subcommand_name({ name: "option", subcommand_path })} has neither a short nor long name."

			InvalidOptionValueType({ option, subcommand_path }) => {
				value_type = 
					match option.expected_value {
						ExpectsValue(type_name) => type_name
						NothingExpected => ""
					}

				"The ${option_at_subcommand_name({ option, subcommand_path })} has value type '${value_type}', which is not kebab-case."
			}

			InvalidParameterValueType({ param, subcommand_path }) => {
				value_name = "parameter '${param.name}'"
				"The ${value_at_subcommand_name({ name: value_name, subcommand_path })} has value type '${param.type}', which is not kebab-case."
			}

			OverrodeSpecialHelpFlag({ option, subcommand_path }) =>
				"The ${option_at_subcommand_name({ option, subcommand_path })} tried to overwrite the built-in -h/--help flag."

			OverrodeSpecialVersionFlag({ option, subcommand_path }) =>
				"The ${option_at_subcommand_name({ option, subcommand_path })} tried to overwrite the built-in -V/--version flag."
			}
	}
}

option_display_name : { short : Str, long : Str, .. } -> Str
option_display_name = |option|
	match (option.short, option.long) {
		("", "") => ""
		(short, "") => "-${short}"
		("", long) => "--${long}"
		(short, long) => "-${short}/--${long}"
	}

option_type_name : { expected_value : ExpectedValue, .. } -> Str
option_type_name = |{ expected_value, .. }|
	match expected_value {
		ExpectsValue(type_name) => full_type_name(type_name)
		NothingExpected => ""
	}

full_type_name : Str -> Str
full_type_name = |type_name|
	if type_name == str_type_name {
		"string"
	} else if type_name == num_type_name {
		"number"
	} else {
		type_name
	}
