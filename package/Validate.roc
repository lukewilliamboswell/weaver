import Base exposing [
	CliConfig,
	ExpectedValue,
	OptionConfig,
	ParameterConfig,
	SubcommandsConfig,
	help_option,
	version_option,
]
import Utils exposing [is_kebab_case]

Validate := [].{
	NameAtSubcommand : { name : Str, subcommand_path : List(Str) }
	OptionAtSubcommand : { option : OptionConfig, subcommand_path : List(Str) }
	ParamAtSubcommand : { param : ParameterConfig, subcommand_path : List(Str) }

	## The types of errors that might be found in a misconfigured CLI.
	CliValidationErr : [
		OverlappingParameterNames({ first : Str, second : Str, subcommand_path : List(Str) }),
		OverlappingOptionNames({ left : OptionAtSubcommand, right : OptionAtSubcommand }),
		DuplicateSubcommandName(NameAtSubcommand),
		RequiredSubcommandsCannotBeEmpty(List(Str)),
		InvalidShortFlagName(NameAtSubcommand),
		InvalidLongFlagName(NameAtSubcommand),
		InvalidCommandName(NameAtSubcommand),
		InvalidParameterName(NameAtSubcommand),
		OptionMustHaveShortOrLongName({ subcommand_path : List(Str) }),
		InvalidOptionValueType(OptionAtSubcommand),
		InvalidParameterValueType(ParamAtSubcommand),
		OverrodeSpecialHelpFlag(OptionAtSubcommand),
		OverrodeSpecialVersionFlag(OptionAtSubcommand),
	]

	## Ensure that a CLI's configuration is valid.
	validate_cli : CliConfig -> Try({}, CliValidationErr)
	validate_cli = |{ name, options, parameters, subcommands, .. }|
		Validate.validate_command({
			name,
			options,
			parent_options: [],
			parameters,
			subcommands,
			subcommand_path: [name],
		})

	validate_command :
		{
			name : Str,
			options : List(OptionConfig),
			parent_options : List(OptionAtSubcommand),
			parameters : List(ParameterConfig),
			subcommands : SubcommandsConfig,
			subcommand_path : List(Str),
		} -> Try({}, CliValidationErr)
	validate_command = |{ name, options, parent_options, parameters, subcommands, subcommand_path }| {
		Validate.ensure_command_is_well_named({ name, subcommand_path })?
		validate_options(options, subcommand_path)?
		validate_parameters(parameters, subcommand_path)?
		Validate.check_if_there_are_overlapping_parameters(parameters, subcommand_path)?

		match subcommands {
			HasSubcommands({ commands: [], required: True }) => {
				err : CliValidationErr
				err = RequiredSubcommandsCannotBeEmpty(subcommand_path)

				Err(err)
			}

			HasSubcommands({ commands, .. }) if !commands.is_empty() => {
				check_duplicate_subcommand_names(commands, subcommand_path)?
				_ = 
					validate_subcommands(
						commands,
						options,
						parent_options,
						subcommand_path,
					)?

				Ok({})
			}

			_no_subcommands => {
				all_options_to_check = 
					options
						.map(|option| { option, subcommand_path })
						.concat(parent_options)

				Validate.check_if_there_are_overlapping_options(all_options_to_check)
			}
		}
	}

	ensure_command_is_well_named : NameAtSubcommand -> Try({}, CliValidationErr)
	ensure_command_is_well_named = |{ name, subcommand_path }|
		if is_kebab_case(name) {
			Ok({})
		} else {
			Err(InvalidCommandName({ name, subcommand_path }))
		}

	ensure_param_is_well_named : NameAtSubcommand -> Try({}, CliValidationErr)
	ensure_param_is_well_named = |{ name, subcommand_path }|
		if is_kebab_case(name) {
			Ok({})
		} else {
			Err(InvalidParameterName({ name, subcommand_path }))
		}

	ensure_option_is_well_named : OptionAtSubcommand -> Try({}, CliValidationErr)
	ensure_option_is_well_named = |{ option, subcommand_path }|
		match (option.short, option.long) {
			("", "") => Err(OptionMustHaveShortOrLongName({ subcommand_path: subcommand_path }))
			(short, "") => Validate.ensure_short_flag_is_well_named({ name: short, subcommand_path: subcommand_path })
			("", long) => Validate.ensure_long_flag_is_well_named({ name: long, subcommand_path: subcommand_path })
			(short, long) => {
				Validate.ensure_short_flag_is_well_named({ name: short, subcommand_path: subcommand_path })?
				Validate.ensure_long_flag_is_well_named({ name: long, subcommand_path: subcommand_path })
			}
		}

	ensure_option_value_type_is_well_named : OptionAtSubcommand -> Try({}, CliValidationErr)
	ensure_option_value_type_is_well_named = |{ option, subcommand_path }|
		match option.expected_value {
			ExpectsValue(type_name) =>
				if is_kebab_case(type_name) {
					Ok({})
				} else {
					Err(InvalidOptionValueType({ option, subcommand_path }))
				}

			NothingExpected => Ok({})
		}

	ensure_param_value_type_is_well_named : ParamAtSubcommand -> Try({}, CliValidationErr)
	ensure_param_value_type_is_well_named = |{ param, subcommand_path }|
		if is_kebab_case(param.type) {
			Ok({})
		} else {
			Err(InvalidParameterValueType({ param, subcommand_path }))
		}

	ensure_short_flag_is_well_named : NameAtSubcommand -> Try({}, CliValidationErr)
	ensure_short_flag_is_well_named = |{ name, subcommand_path }|
		if name.count_utf8_bytes() != 1 or name == "-" {
			Err(InvalidShortFlagName({ name, subcommand_path }))
		} else {
			Ok({})
		}

	ensure_long_flag_is_well_named : NameAtSubcommand -> Try({}, CliValidationErr)
	ensure_long_flag_is_well_named = |{ name, subcommand_path }|
		if name.count_utf8_bytes() > 1 and is_kebab_case(name) {
			Ok({})
		} else {
			Err(InvalidLongFlagName({ name, subcommand_path }))
		}

	check_if_there_are_overlapping_options : List(OptionAtSubcommand) -> Try({}, CliValidationErr)
	check_if_there_are_overlapping_options = |options|
		check_option_pairs(options)

	check_if_there_are_overlapping_parameters : List(ParameterConfig), List(Str) -> Try({}, CliValidationErr)
	check_if_there_are_overlapping_parameters = |parameters, subcommand_path|
		check_parameter_pairs(parameters, subcommand_path)
}

validate_options : List(OptionConfig), List(Str) -> Try({}, Validate.CliValidationErr)
validate_options = |options, subcommand_path|
	match options {
		[] => Ok({})
		[option, .. as rest] => {
			Validate.ensure_option_is_well_named({ option, subcommand_path })?
			Validate.ensure_option_value_type_is_well_named({ option, subcommand_path })?
			validate_options(rest, subcommand_path)
		}
	}

validate_parameters : List(ParameterConfig), List(Str) -> Try({}, Validate.CliValidationErr)
validate_parameters = |parameters, subcommand_path|
	match parameters {
		[] => Ok({})
		[param, .. as rest] => {
			Validate.ensure_param_is_well_named({ name: param.name, subcommand_path })?
			Validate.ensure_param_value_type_is_well_named({ param, subcommand_path })?
			validate_parameters(rest, subcommand_path)
		}
	}

validate_subcommands : List((Str, Base.SubcommandConfig)), List(OptionConfig), List(Validate.OptionAtSubcommand), List(Str) -> Try({}, Validate.CliValidationErr)
validate_subcommands = |subcommands, options, parent_options, subcommand_path|
	match subcommands {
		[] => Ok({})
		[(subcommand_name, subcommand), .. as rest] => {
			updated_parent_options = 
				options
					.map(|option| { option, subcommand_path })
					.concat(parent_options)

			Validate.validate_command({
				name: subcommand_name,
				options: subcommand.options,
				parent_options: updated_parent_options,
				parameters: subcommand.parameters,
				subcommands: subcommand.subcommands,
				subcommand_path: subcommand_path.append(subcommand_name),
			})?

			validate_subcommands(rest, options, parent_options, subcommand_path)
		}
	}

check_parameter_pairs : List(ParameterConfig), List(Str) -> Try({}, Validate.CliValidationErr)
check_parameter_pairs = |parameters, subcommand_path|
	match parameters {
		[] => Ok({})
		[first, .. as rest] => {
			check_parameter_against_rest(first, rest, subcommand_path)?
			check_parameter_pairs(rest, subcommand_path)
		}
	}

check_duplicate_subcommand_names : List((Str, Base.SubcommandConfig)), List(Str) -> Try({}, Validate.CliValidationErr)
check_duplicate_subcommand_names = |subcommands, subcommand_path|
	match subcommands {
		[] => Ok({})
		[(name, _), .. as rest] =>
			if rest.any(|(other_name, _)| other_name == name) {
				Err(DuplicateSubcommandName({ name, subcommand_path }))
			} else {
				check_duplicate_subcommand_names(rest, subcommand_path)
			}
		}

check_parameter_against_rest : ParameterConfig, List(ParameterConfig), List(Str) -> Try({}, Validate.CliValidationErr)
check_parameter_against_rest = |first, rest, subcommand_path|
	match rest {
		[] => Ok({})
		[second, .. as remaining] =>
			if first.name == second.name {
				Err(OverlappingParameterNames({ first: first.name, second: second.name, subcommand_path }))
			} else {
				check_parameter_against_rest(first, remaining, subcommand_path)
			}
		}

check_option_pairs : List(Validate.OptionAtSubcommand) -> Try({}, Validate.CliValidationErr)
check_option_pairs = |options|
	match options {
		[] => Ok({})
		[first, .. as rest] => {
			check_option_against_rest(first, rest)?
			check_option_pairs(rest)
		}
	}

check_option_against_rest : Validate.OptionAtSubcommand, List(Validate.OptionAtSubcommand) -> Try({}, Validate.CliValidationErr)
check_option_against_rest = |first, rest|
	match rest {
		[] => Ok({})
		[second, .. as remaining] =>
			if options_overlap(first.option, second.option) {
				if repeated_builtin_at_nested_scope(first, second) {
					check_option_against_rest(first, remaining)
				} else if options_overlap(first.option, help_option) or options_overlap(second.option, help_option) {
					Err(OverrodeSpecialHelpFlag(non_builtin_option(first, second, help_option)))
				} else if options_overlap(first.option, version_option) or options_overlap(second.option, version_option) {
					Err(OverrodeSpecialVersionFlag(non_builtin_option(first, second, version_option)))
				} else {
					Err(OverlappingOptionNames({ left: first, right: second }))
				}
			} else {
				check_option_against_rest(first, remaining)
			}
		}

options_overlap : OptionConfig, OptionConfig -> Bool
options_overlap = |left, right| {
	short_overlap = left.short != "" and left.short == right.short
	long_overlap = left.long != "" and left.long == right.long

	short_overlap or long_overlap
}

repeated_builtin_at_nested_scope : Validate.OptionAtSubcommand, Validate.OptionAtSubcommand -> Bool
repeated_builtin_at_nested_scope = |left, right| {
	different_scopes = left.subcommand_path != right.subcommand_path
	both_help = left.option == help_option and right.option == help_option
	both_version = left.option == version_option and right.option == version_option

	different_scopes and (both_help or both_version)
}

non_builtin_option : Validate.OptionAtSubcommand, Validate.OptionAtSubcommand, OptionConfig -> Validate.OptionAtSubcommand
non_builtin_option = |left, right, builtin|
	if left.option == builtin {
		right
	} else {
		left
	}

test_option : Str, Str -> OptionConfig
test_option = |short, long| {
	short,
	long,
	help: "test option",
	expected_value: NothingExpected,
	plurality: Optional,
	required: False,
}

## Options cannot reuse a short name in the same command.
expect {
	left = { option: test_option("a", "alpha"), subcommand_path: ["app"] }
	right = { option: test_option("a", "another"), subcommand_path: ["app"] }

	Validate.check_if_there_are_overlapping_options([left, right])
		== Err(OverlappingOptionNames({ left, right }))
}

## Options cannot reuse a long name in the same command.
expect {
	left = { option: test_option("a", "value"), subcommand_path: ["app"] }
	right = { option: test_option("b", "value"), subcommand_path: ["app"] }

	Validate.check_if_there_are_overlapping_options([left, right])
		== Err(OverlappingOptionNames({ left, right }))
}

## A short name may equal another option's long name because their syntax differs.
expect {
	left = { option: test_option("a", "alpha"), subcommand_path: ["app"] }
	right = { option: test_option("b", "a"), subcommand_path: ["app"] }

	Validate.check_if_there_are_overlapping_options([left, right]) == Ok({})
}

## A subcommand cannot shadow an ancestor option that remains in scope.
expect {
	child = { option: test_option("a", "child"), subcommand_path: ["app", "run"] }
	parent = { option: test_option("a", "parent"), subcommand_path: ["app"] }

	Validate.check_if_there_are_overlapping_options([child, parent])
		== Err(OverlappingOptionNames({ left: child, right: parent }))
}

## User-defined options cannot override the built-in help aliases.
expect {
	custom = { option: test_option("h", "custom-help"), subcommand_path: ["app"] }
	builtin = { option: help_option, subcommand_path: ["app"] }

	Validate.check_if_there_are_overlapping_options([custom, builtin])
		== Err(OverrodeSpecialHelpFlag(custom))
}

## User-defined options cannot override the built-in version aliases.
expect {
	custom = { option: test_option("x", "version"), subcommand_path: ["app"] }
	builtin = { option: version_option, subcommand_path: ["app"] }

	Validate.check_if_there_are_overlapping_options([custom, builtin])
		== Err(OverrodeSpecialVersionFlag(custom))
}

## Nested commands may each include Weaver's same built-in help and version flags.
expect {
	root_help = { option: help_option, subcommand_path: ["app"] }
	child_help = { option: help_option, subcommand_path: ["app", "run"] }
	root_version = { option: version_option, subcommand_path: ["app"] }
	child_version = { option: version_option, subcommand_path: ["app", "run"] }

	Validate.check_if_there_are_overlapping_options([child_help, child_version, root_help, root_version]) == Ok({})
}

empty_subcommand_config : Base.SubcommandConfig
empty_subcommand_config = {
	description: "",
	options: [],
	parameters: [],
	subcommands: NoSubcommands,
}

## Duplicate subcommand declarations are rejected before either can be lost.
expect {
	config : CliConfig
	config = {
		name: "app",
		version: "",
		authors: [],
		description: "",
		options: [],
		parameters: [],
		subcommands: HasSubcommands({
			commands: [("run", empty_subcommand_config), ("run", empty_subcommand_config)],
			required: False,
		}),
	}

	Validate.validate_cli(config)
		== Err(DuplicateSubcommandName({ name: "run", subcommand_path: ["app"] }))
}

## A required subcommand set must contain at least one possible command.
expect {
	config : CliConfig
	config = {
		name: "app",
		version: "",
		authors: [],
		description: "",
		options: [],
		parameters: [],
		subcommands: HasSubcommands({ commands: [], required: True }),
	}

	Validate.validate_cli(config)
		== Err(RequiredSubcommandsCannotBeEmpty(["app"]))
}

## Short names must be exactly one invokable byte and cannot be the delimiter.
expect {
	actual =
		Str.join_with(
			[
				Str.inspect(Validate.ensure_short_flag_is_well_named({ name: "ab", subcommand_path: ["app"] })),
				Str.inspect(Validate.ensure_short_flag_is_well_named({ name: "é", subcommand_path: ["app"] })),
				Str.inspect(Validate.ensure_short_flag_is_well_named({ name: "-", subcommand_path: ["app"] })),
				Str.inspect(Validate.ensure_short_flag_is_well_named({ name: "a", subcommand_path: ["app"] })),
			],
			"\n",
		)

	actual
		==
		\\Err(InvalidShortFlagName({ name: "ab", subcommand_path: ["app"] }))
		\\Err(InvalidShortFlagName({ name: "é", subcommand_path: ["app"] }))
		\\Err(InvalidShortFlagName({ name: "-", subcommand_path: ["app"] }))
		\\Ok({})
}

## Long option names must be multi-character kebab-case identifiers.
expect {
	actual =
		Str.join_with(
			[
				Str.inspect(Validate.ensure_long_flag_is_well_named({ name: "a", subcommand_path: ["app"] })),
				Str.inspect(Validate.ensure_long_flag_is_well_named({ name: "Alpha", subcommand_path: ["app"] })),
				Str.inspect(Validate.ensure_long_flag_is_well_named({ name: "alpha-value", subcommand_path: ["app"] })),
			],
			"\n",
		)

	actual
		==
		\\Err(InvalidLongFlagName({ name: "a", subcommand_path: ["app"] }))
		\\Err(InvalidLongFlagName({ name: "Alpha", subcommand_path: ["app"] }))
		\\Ok({})
}

## Options must have at least one name and valid value-type metadata.
expect {
	nameless = test_option("", "")
	bad_type = { ..test_option("a", "alpha"), expected_value: ExpectsValue("Bad Type") }

	actual =
		Str.join_with(
			[
				Str.inspect(Validate.ensure_option_is_well_named({ option: nameless, subcommand_path: ["app"] })),
				Str.inspect(Validate.ensure_option_value_type_is_well_named({ option: bad_type, subcommand_path: ["app"] })),
			],
			"\n",
		)

	actual
		==
		\\Err(OptionMustHaveShortOrLongName({ subcommand_path: ["app"] }))
		\\Err(InvalidOptionValueType({ option: { expected_value: ExpectsValue("Bad Type"), help: "test option", long: "alpha", plurality: Optional, required: False, short: "a" }, subcommand_path: ["app"] }))
}

## Command, parameter, and parameter-type names use the same kebab-case rules.
expect {
	bad_param = { name: "input", help: "Input.", type: "Bad Type", plurality: One, required: True }

	actual =
		Str.join_with(
			[
				Str.inspect(Validate.ensure_command_is_well_named({ name: "Bad Command", subcommand_path: ["app"] })),
				Str.inspect(Validate.ensure_param_is_well_named({ name: "Bad Param", subcommand_path: ["app"] })),
				Str.inspect(Validate.ensure_param_value_type_is_well_named({ param: bad_param, subcommand_path: ["app"] })),
			],
			"\n",
		)

	actual
		==
		\\Err(InvalidCommandName({ name: "Bad Command", subcommand_path: ["app"] }))
		\\Err(InvalidParameterName({ name: "Bad Param", subcommand_path: ["app"] }))
		\\Err(InvalidParameterValueType({ param: { help: "Input.", name: "input", plurality: One, required: True, type: "Bad Type" }, subcommand_path: ["app"] }))
}

## Positional parameter names cannot overlap within one command.
expect {
	first = { name: "input", help: "First.", type: "str", plurality: One, required: True }
	second = { name: "input", help: "Second.", type: "str", plurality: Optional, required: False }

	Validate.check_if_there_are_overlapping_parameters([first, second], ["app"])
		== Err(OverlappingParameterNames({ first: "input", second: "input", subcommand_path: ["app"] }))
}
