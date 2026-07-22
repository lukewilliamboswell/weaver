import Base exposing [
	CliConfig,
	ExpectedValue,
	OptionConfig,
	ParameterConfig,
	SubcommandsConfig,
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
			HasSubcommands(subcommand_configs) if !subcommand_configs.is_empty() => {
				_ = 
					validate_subcommands(
						subcommand_configs.to_list(),
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
		if name.count_utf8_bytes() != 1 {
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
	check_if_there_are_overlapping_options = |_options|
	# TODO: restore option-overlap validation once current Roc supports the
	# needed comparison ergonomics without compiler issues.
		Ok({})

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
