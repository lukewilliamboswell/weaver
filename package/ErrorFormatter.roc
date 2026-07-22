import Base exposing [ArgExtractErr, ExpectedValue, TextStyle, num_type_name, str_type_name]
import Terminal
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

			UnrecognizedSubcommand(command) =>
				"The subcommand ${Str.inspect(Path.display(command))} was not recognized."

			UnrecognizedShortArg(short) =>
				"The argument -${short} was not recognized."

			UnrecognizedLongArg(long) =>
				"The argument --${long} was not recognized."

			ExtraParamProvided(param) =>
				"The parameter ${Str.inspect(Path.display(param))} was not expected."
			}

	## Render an argument extraction failure as a complete terminal report.
	render_arg_extract_err : ArgExtractErr, { command : Str, usage : Str }, TextStyle -> Str
	render_arg_extract_err = |err, { command, usage }, text_style| {
		metadata = arg_error_metadata(err, command)
		render_report(
			metadata.title,
			ErrorFormatter.format_arg_extract_err(err),
			usage,
			metadata.hint,
			text_style,
		)
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

			DuplicateSubcommandName({ name, subcommand_path }) =>
				"The command '${name}' is declared more than once for '${Str.join_with(subcommand_path, " ")}'."

			RequiredSubcommandsCannotBeEmpty(subcommand_path) =>
				"The command '${Str.join_with(subcommand_path, " ")}' requires a subcommand but declares none."

			InvalidShortFlagName({ name, subcommand_path }) => {
				value_name = "option '-${name}'"
				"The ${value_at_subcommand_name({ name: value_name, subcommand_path })} must be a single-byte character other than '-'."
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

	## Render a CLI configuration failure as a complete terminal report.
	render_cli_validation_err : CliValidationErr, TextStyle -> Str
	render_cli_validation_err = |err, text_style| {
		metadata = validation_error_metadata(err)
		render_report(
			metadata.title,
			ErrorFormatter.format_cli_validation_err(err),
			"",
			metadata.hint,
			text_style,
		)
	}
}

DiagnosticMetadata : { title : Str, hint : Str }

arg_error_metadata : ArgExtractErr, Str -> DiagnosticMetadata
arg_error_metadata = |err, command| {
	help_hint = "Run `${command} --help` to see the available arguments."

	match err {
		NoSubcommandCalled => {
			title: "MISSING COMMAND",
			hint: "Run `${command} --help` to see the available commands.",
		}
		MissingOption(option) => {
			title: "MISSING OPTION",
			hint: "Provide `${option_display_name(option)} ${option_type_name(option)}` as shown in Usage.",
		}
		OptionCanOnlyBeSetOnce(option) => {
			title: "DUPLICATE OPTION",
			hint: "Remove the repeated `${option_display_name(option)}` option.",
		}
		NoValueProvidedForOption(option) => {
			title: "MISSING OPTION VALUE",
			hint: "Provide a ${option_type_name(option)} after `${option_display_name(option)}`.",
		}
		OptionDoesNotExpectValue(option) => {
			title: "UNEXPECTED OPTION VALUE",
			hint: "Pass `${option_display_name(option)}` without a value.",
		}
		CannotUsePartialShortGroupAsValue(option, _) => {
			title: "INVALID SHORT OPTION GROUP",
			hint: "Pass `${option_display_name(option)}` separately or move it to the end of the short option group.",
		}
		ValueOptionMustBeLastInShortGroup(option, _) => {
			title: "INVALID SHORT OPTION GROUP",
			hint: "Move `${option_display_name(option)}` to the end of the group or pass it separately.",
		}
		InvalidOptionValue(value_err, option) => {
			hint = 
				match value_err {
					InvalidNumStr => "Provide a valid number for `${option_display_name(option)}`."
					InvalidValue(_) => "Provide a value accepted by `${option_display_name(option)}`."
					InvalidUtf8 => "Use a value for `${option_display_name(option)}` that can be decoded as UTF-8."
				}

			{ title: "INVALID OPTION VALUE", hint }
		}
		InvalidParamValue(value_err, parameter) => {
			hint = 
				match value_err {
					InvalidNumStr => "Provide a valid number for `<${parameter.name}>`."
					InvalidValue(_) => "Provide a value accepted by `<${parameter.name}>`."
					InvalidUtf8 => "Use a value for `<${parameter.name}>` that can be decoded as UTF-8."
				}

			{ title: "INVALID ARGUMENT VALUE", hint }
		}
		MissingParam(parameter) => {
			title: "MISSING ARGUMENT",
			hint: "Provide `<${parameter.name}>` in the position shown in Usage.",
		}
		UnrecognizedSubcommand(_) => {
			title: "UNRECOGNIZED COMMAND",
			hint: "Run `${command} --help` to see the available commands.",
		}
		UnrecognizedShortArg(_) | UnrecognizedLongArg(_) => {
			title: "UNRECOGNIZED ARGUMENT",
			hint: help_hint,
		}
		ExtraParamProvided(_) => {
			title: "UNEXPECTED ARGUMENT",
			hint: "Remove the extra value or place it where Usage expects a positional argument.",
		}
	}
}

validation_error_metadata : CliValidationErr -> DiagnosticMetadata
validation_error_metadata = |err|
	match err {
		OverlappingOptionNames(_) => {
			title: "OVERLAPPING OPTIONS",
			hint: "Give each option a unique short and long name across its command path.",
		}
		OverlappingParameterNames(_) => {
			title: "OVERLAPPING ARGUMENTS",
			hint: "Give each positional argument a unique name within its command.",
		}
		DuplicateSubcommandName(_) => {
			title: "DUPLICATE COMMAND",
			hint: "Declare each subcommand name only once beneath its parent command.",
		}
		RequiredSubcommandsCannotBeEmpty(_) => {
			title: "MISSING COMMAND",
			hint: "Declare at least one subcommand or make the subcommand group optional.",
		}
		InvalidShortFlagName(_) => {
			title: "INVALID SHORT OPTION NAME",
			hint: "Use one single-byte character other than `-` for a short option.",
		}
		InvalidLongFlagName(_) => {
			title: "INVALID LONG OPTION NAME",
			hint: "Use a kebab-case long name containing at least two characters.",
		}
		InvalidCommandName(_) => {
			title: "INVALID COMMAND NAME",
			hint: "Use a kebab-case command name.",
		}
		InvalidParameterName(_) => {
			title: "INVALID ARGUMENT NAME",
			hint: "Use a kebab-case positional argument name.",
		}
		OptionMustHaveShortOrLongName(_) => {
			title: "UNNAMED OPTION",
			hint: "Give the option a short name, a long name, or both.",
		}
		InvalidOptionValueType(_) => {
			title: "INVALID OPTION TYPE",
			hint: "Use a kebab-case option value type.",
		}
		InvalidParameterValueType(_) => {
			title: "INVALID ARGUMENT TYPE",
			hint: "Use a kebab-case positional argument value type.",
		}
		OverrodeSpecialHelpFlag(_) => {
			title: "RESERVED HELP OPTION",
			hint: "Remove this option; Weaver provides `-h` and `--help` automatically.",
		}
		OverrodeSpecialVersionFlag(_) => {
			title: "RESERVED VERSION OPTION",
			hint: "Remove this option; Weaver provides `-V` and `--version` automatically.",
		}
	}

render_report : Str, Str, Str, Str, TextStyle -> Str
render_report = |title, summary, usage, hint, text_style| {
	rule = Str.repeat("─", title.count_utf8_bytes() + 2)
	top = Terminal.render([Terminal.frame("┌${rule}┐")], text_style)
	middle = 
		Terminal.render(
			[Terminal.frame("│ "), Terminal.heading(title), Terminal.frame(" │")],
			text_style,
		)
	bottom = Terminal.render([Terminal.frame("└${rule}┘")], text_style)
	wrapped_summary = 
		Terminal.wrap(
			summary,
			{ first_indent: "", continuation_indent: "", width: 80 },
		)
	plain_hint = 
		Terminal.wrap(
			"Tip: ${hint}",
			{ first_indent: "", continuation_indent: "     ", width: 80 },
		)
	styled_hint = Terminal.render([Terminal.hint(plain_hint)], text_style)
	body = [wrapped_summary, usage, styled_hint].keep_if(|section| !section.is_empty())

	"${top}\n${middle}\n${bottom}\n\n${Str.join_with(body, "\n\n")}"
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

error_test_option = {
	short: "a",
	long: "alpha",
	help: "Alpha.",
	expected_value: ExpectsValue("num"),
	plurality: One,
	required: True,
}

error_test_parameter = {
	name: "input",
	help: "Input.",
	type: "str",
	plurality: One,
	required: True,
}

## Every runtime extraction failure has a stable diagnostic title.
expect {
	errors : List(ArgExtractErr)
	errors = [
		NoSubcommandCalled,
		MissingOption(error_test_option),
		OptionCanOnlyBeSetOnce(error_test_option),
		NoValueProvidedForOption(error_test_option),
		OptionDoesNotExpectValue(error_test_option),
		CannotUsePartialShortGroupAsValue(error_test_option, ["a", "1"]),
		ValueOptionMustBeLastInShortGroup(error_test_option, ["a", "b"]),
		InvalidOptionValue(InvalidNumStr, error_test_option),
		InvalidParamValue(InvalidUtf8, error_test_parameter),
		MissingParam(error_test_parameter),
		UnrecognizedSubcommand(Path.utf8("wat")),
		UnrecognizedShortArg("x"),
		UnrecognizedLongArg("wat"),
		ExtraParamProvided(Path.utf8("tail")),
	]

	titles = errors.map(|err| arg_error_metadata(err, "app").title)

	Str.join_with(titles, "\n")
		==
		\\MISSING COMMAND
		\\MISSING OPTION
		\\DUPLICATE OPTION
		\\MISSING OPTION VALUE
		\\UNEXPECTED OPTION VALUE
		\\INVALID SHORT OPTION GROUP
		\\INVALID SHORT OPTION GROUP
		\\INVALID OPTION VALUE
		\\INVALID ARGUMENT VALUE
		\\MISSING ARGUMENT
		\\UNRECOGNIZED COMMAND
		\\UNRECOGNIZED ARGUMENT
		\\UNRECOGNIZED ARGUMENT
		\\UNEXPECTED ARGUMENT
}

## Every configuration validation failure has a stable diagnostic title.
expect {
	option_at = { option: error_test_option, subcommand_path: ["app"] }
	param_at = { param: error_test_parameter, subcommand_path: ["app"] }
	errors : List(CliValidationErr)
	errors = [
		OverlappingOptionNames({ left: option_at, right: option_at }),
		OverlappingParameterNames({ first: "input", second: "input", subcommand_path: ["app"] }),
		DuplicateSubcommandName({ name: "run", subcommand_path: ["app"] }),
		RequiredSubcommandsCannotBeEmpty(["app"]),
		InvalidShortFlagName({ name: "ab", subcommand_path: ["app"] }),
		InvalidLongFlagName({ name: "A", subcommand_path: ["app"] }),
		InvalidCommandName({ name: "Bad", subcommand_path: ["app"] }),
		InvalidParameterName({ name: "Bad", subcommand_path: ["app"] }),
		OptionMustHaveShortOrLongName({ subcommand_path: ["app"] }),
		InvalidOptionValueType(option_at),
		InvalidParameterValueType(param_at),
		OverrodeSpecialHelpFlag(option_at),
		OverrodeSpecialVersionFlag(option_at),
	]

	titles = errors.map(|err| validation_error_metadata(err).title)

	Str.join_with(titles, "\n")
		==
		\\OVERLAPPING OPTIONS
		\\OVERLAPPING ARGUMENTS
		\\DUPLICATE COMMAND
		\\MISSING COMMAND
		\\INVALID SHORT OPTION NAME
		\\INVALID LONG OPTION NAME
		\\INVALID COMMAND NAME
		\\INVALID ARGUMENT NAME
		\\UNNAMED OPTION
		\\INVALID OPTION TYPE
		\\INVALID ARGUMENT TYPE
		\\RESERVED HELP OPTION
		\\RESERVED VERSION OPTION
}

## Plain runtime diagnostics are exact, multiline terminal reports.
expect {
	actual = ErrorFormatter.render_arg_extract_err(
		UnrecognizedLongArg("wat"),
		{ command: "app", usage: "Usage:\n  app [OPTIONS]" },
		Plain,
	)

	actual
		==
		\\┌───────────────────────┐
		\\│ UNRECOGNIZED ARGUMENT │
		\\└───────────────────────┘
		\\
		\\The argument --wat was not recognized.
		\\
		\\Usage:
		\\  app [OPTIONS]
		\\
		\\Tip: Run `app --help` to see the available arguments.
}

## Colored runtime diagnostics style the frame, title, and hint without changing layout.
expect {
	actual = ErrorFormatter.render_arg_extract_err(
		UnrecognizedLongArg("wat"),
		{ command: "app", usage: "Usage:\n  app [OPTIONS]" },
		Color,
	)

	actual
		==
		\\\u(001b)[90m┌───────────────────────┐\u(001b)[0m
		\\\u(001b)[90m│ \u(001b)[0m\u(001b)[1m\u(001b)[36mUNRECOGNIZED ARGUMENT\u(001b)[0m\u(001b)[90m │\u(001b)[0m
		\\\u(001b)[90m└───────────────────────┘\u(001b)[0m
		\\
		\\The argument --wat was not recognized.
		\\
		\\Usage:
		\\  app [OPTIONS]
		\\
		\\\u(001b)[1m\u(001b)[32mTip: Run `app --help` to see the available arguments.\u(001b)[0m
}

## Validation diagnostics use the same report format with a targeted hint.
expect {
	actual = ErrorFormatter.render_cli_validation_err(
		InvalidLongFlagName({ name: "A", subcommand_path: ["app"] }),
		Plain,
	)

	actual
		==
		\\┌──────────────────────────┐
		\\│ INVALID LONG OPTION NAME │
		\\└──────────────────────────┘
		\\
		\\The option '--A' is not kebab-case and at least two characters.
		\\
		\\Tip: Use a kebab-case long name containing at least two characters.
}
