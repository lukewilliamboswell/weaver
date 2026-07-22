import Base exposing [
	CliConfig,
	OptionConfig,
	ParameterConfig,
	SubcommandConfig,
	SubcommandsConfig,
	TextStyle,
]
import Terminal
import Utils exposing [to_upper_case]

terminal_width : U64
terminal_width = 80

Help := [].{

	## Walks the subcommand tree from the root CLI config and returns the target
	## command config, falling back to the root command if the path is invalid.
	find_subcommand_or_default : CliConfig, List(Str) -> { config : CliConfig, subcommand_path : List(Str) }
	find_subcommand_or_default = |config, subcommand_path| {
		base_command = {
			description: config.description,
			options: config.options,
			parameters: config.parameters,
			subcommands: config.subcommands,
		}

		match Help.find_subcommand(base_command, subcommand_path.drop_first(1)) {
			Err(KeyNotFound) => { config, subcommand_path }
			Ok(command) => {
				config: {
					name: config.name,
					version: config.version,
					authors: config.authors,
					description: command.description,
					options: command.options,
					parameters: command.parameters,
					subcommands: command.subcommands,
				},
				subcommand_path,
			}
		}
	}

	## Searches a command's config for subcommands recursively.
	find_subcommand : SubcommandConfig, List(Str) -> Try(SubcommandConfig, [KeyNotFound])
	find_subcommand = |command, path|
		match path {
			[] => Ok(command)
			[first, .. as rest] =>
				match command.subcommands {
					NoSubcommands => Err(KeyNotFound)
					HasSubcommands({ commands, .. }) => {
						subcommand = find_command(commands, first)?
						Help.find_subcommand(subcommand, rest)
					}
				}
			}

	## Render the help text for a command at or under the root config.
	help_text : CliConfig, List(Str), TextStyle -> Str
	help_text = |base_config, path, text_style| {
		{ config, subcommand_path } = Help.find_subcommand_or_default(base_config, path)
		{ version, authors, description, options, parameters, subcommands, .. } = config

		name = Str.join_with(subcommand_path, " ")

		styled_top_line = 
			Terminal.render(
				filter_non_empty_segments([
					Terminal.heading(name),
					Terminal.muted(version),
				]),
				text_style,
			)

		authors_text = 
			if authors.is_empty() {
				""
			} else {
				styled_authors = Terminal.render([Terminal.muted(Str.join_with(authors, " "))], text_style)
				"\n${styled_authors}"
			}

		description_text = 
			if description.is_empty() {
				""
			} else {
				wrapped_description = 
					Terminal.wrap(
						description,
						{ first_indent: "", continuation_indent: "", width: terminal_width },
					)

				"\n\n${wrapped_description}"
			}

		subcommands_text = 
			match subcommands {
				HasSubcommands({ commands, .. }) if !commands.is_empty() =>
					commands_help(subcommands, text_style)

				_no_subcommands => ""
			}

		parameters_text = 
			if parameters.is_empty() {
				""
			} else {
				parameters_help(parameters, text_style)
			}

		options_text = 
			if options.is_empty() {
				""
			} else {
				options_help(options, text_style)
			}

		bottom_sections = 
			join_lines_with(filter_non_empty([subcommands_text, parameters_text, options_text]), "\n\n")

		"${styled_top_line}${authors_text}${description_text}\n\n${Help.usage_help(config, subcommand_path, text_style)}\n\n${bottom_sections}"
	}

	## Render just the usage text for a command at or under the root config.
	usage_help : CliConfig, List(Str), TextStyle -> Str
	usage_help = |config, path, text_style| {
		{ config: command_config, subcommand_path } = Help.find_subcommand_or_default(config, path)
		{ options, parameters, subcommands, .. } = command_config

		name = Str.join_with(subcommand_path, " ")

		required_options = 
			filter_required_options(options).map(option_simple_name_formatter)

		other_options = 
			if required_options.len() == options.len() {
				[]
			} else {
				["[OPTIONS]"]
			}

		params_strings = 
			parameters.map(
				|param| {
					value = 
						match param.plurality {
							Optional | One => "<${param.name}>"
							Many => "<${param.name}>..."
						}

					if param.required {
						value
					} else {
						"[${value}]"
					}
				},
			)

		subcommand_strings = 
			match subcommands {
				HasSubcommands({ commands, required }) if !commands.is_empty() =>
					if required {
						["<COMMAND>"]
					} else {
						["[COMMAND]"]
					}

				_other => []
			}

		usage_parts = 
			join_lines_with(required_options.concat(other_options).concat(params_strings).concat(subcommand_strings), " ")

		styled_heading = Terminal.render([Terminal.section("Usage:")], text_style)
		plain_usage = 
			Terminal.wrap(
				if usage_parts.is_empty() {
					name
				} else {
					"${name} ${usage_parts}"
				},
				{ first_indent: "  ", continuation_indent: "  ", width: terminal_width },
			)
		styled_usage = Terminal.render([Terminal.label(plain_usage)], text_style)

		"${styled_heading}\n${styled_usage}"
	}
}

commands_help : SubcommandsConfig, TextStyle -> Str
commands_help = |subcommands, text_style| {
	commands = 
		match subcommands {
			NoSubcommands => []
			HasSubcommands({ commands: declared_commands, .. }) => declared_commands
		}

	aligned_commands = 
		align_two_columns(commands.map(|(name, sub_config)| { label: name, help: sub_config.description }), text_style)

	styled_heading = Terminal.render([Terminal.section("Commands:")], text_style)

	"${styled_heading}\n${Str.join_with(aligned_commands, "\n")}"
}

find_command : List((Str, SubcommandConfig)), Str -> Try(SubcommandConfig, [KeyNotFound])
find_command = |commands, target|
	match commands {
		[] => Err(KeyNotFound)
		[(name, command), .. as rest] =>
			if name == target {
				Ok(command)
			} else {
				find_command(rest, target)
			}
		}

parameters_help : List(ParameterConfig), TextStyle -> Str
parameters_help = |params, text_style| {
	formatted_params = 
		align_two_columns(
			params.map(
				|param| {
					ellipsis = 
						match param.plurality {
							Optional | One => ""
							Many => "..."
						}

					{ label: "<${param.name}${ellipsis}>", help: param.help }
				},
			),
			text_style,
		)

	styled_heading = Terminal.render([Terminal.section("Arguments:")], text_style)

	"${styled_heading}\n${Str.join_with(formatted_params, "\n")}"
}

option_name_formatter : OptionConfig -> Str
option_name_formatter = |{ short, long, expected_value, .. }| {
	short_name = 
		if short != "" {
			"-${short}"
		} else {
			""
		}

	long_name = 
		if long != "" {
			"--${long}"
		} else {
			""
		}

	type_name = 
		match expected_value {
			NothingExpected => ""
			ExpectsValue(name) => " ${to_upper_case(name)}"
		}

	join_lines_with(filter_non_empty([short_name, long_name]).map(|name| "${name}${type_name}"), ", ")
}

option_simple_name_formatter : OptionConfig -> Str
option_simple_name_formatter = |{ short, long, expected_value, .. }| {
	short_name = 
		if short != "" {
			"-${short}"
		} else {
			""
		}

	long_name = 
		if long != "" {
			"--${long}"
		} else {
			""
		}

	type_name = 
		match expected_value {
			NothingExpected => ""
			ExpectsValue(name) => " ${to_upper_case(name)}"
		}

	"${join_lines_with(filter_non_empty([short_name, long_name]), "/")}${type_name}"
}

options_help : List(OptionConfig), TextStyle -> Str
options_help = |options, text_style| {
	formatted_options = 
		align_two_columns(options.map(|option| { label: option_name_formatter(option), help: option.help }), text_style)

	styled_heading = Terminal.render([Terminal.section("Options:")], text_style)

	"${styled_heading}\n${Str.join_with(formatted_options, "\n")}"
}

indent_multiline_string_by : Str, U64 -> Str
indent_multiline_string_by = |string, indent_amount| {
	indentation = Str.repeat(" ", indent_amount)

	indent_lines(string.split_on("\n"), indentation, True, [])
}

HelpColumn : { label : Str, help : Str }

align_two_columns : List(HelpColumn), TextStyle -> List(Str)
align_two_columns = |columns, text_style| {
	max_first_column_len = 
		max_or_zero(columns.map(|{ label, .. }| label.count_utf8_bytes()))

	columns.map(
		|{ label, help }| {
			buffer = 
				Str.repeat(" ", max_first_column_len - label.count_utf8_bytes())

			available_width = terminal_width - (max_first_column_len + 4).min(terminal_width - 1)
			wrapped_help = 
				Terminal.wrap(
					help,
					{ first_indent: "", continuation_indent: "", width: available_width },
				)
			second_shifted = indent_multiline_string_by(wrapped_help, max_first_column_len + 4)

			styled_label = Terminal.render([Terminal.label(label), Terminal.plain(buffer)], text_style)

			"  ${styled_label}  ${second_shifted}"
		},
	)
}

filter_non_empty_segments : List(Terminal.Segment) -> List(Terminal.Segment)
filter_non_empty_segments = |segments| {
	non_empty = segments.keep_if(|segment| !segment.text.is_empty())

	match non_empty {
		[] => []
		[first, .. as rest] =>
			rest.fold([first], |out, segment| out.append(Terminal.plain(" ")).append(segment))
		}
}

filter_non_empty : List(Str) -> List(Str)
filter_non_empty = |values|
	match values {
		[] => []
		[first, .. as rest] =>
			if first.is_empty() {
				filter_non_empty(rest)
			} else {
				[first].concat(filter_non_empty(rest))
			}
		}

join_lines_with : List(Str), Str -> Str
join_lines_with = |values, separator|
	Str.join_with(values, separator)

filter_required_options : List(OptionConfig) -> List(OptionConfig)
filter_required_options = |options|
	options.keep_if(|option| option.required)

max_or_zero : List(U64) -> U64
max_or_zero = |values|
	match values {
		[] => 0
		[first, .. as rest] => max_help(rest, first)
	}

max_help : List(U64), U64 -> U64
max_help = |values, current|
	match values {
		[] => current
		[first, .. as rest] => max_help(rest, current.max(first))
	}

indent_lines : List(Str), Str, Bool, List(Str) -> Str
indent_lines = |lines, indentation, is_first, out|
	match lines {
		[] => Str.join_with(out, "\n")
		[line, .. as rest] => {
			rendered = 
				if is_first {
					line
				} else {
					"${indentation}${line}"
				}

			indent_lines(rest, indentation, False, out.append(rendered))
		}
	}

## Usage distinguishes required inputs from optional, defaulted, and variadic inputs.
expect {
	required_option = {
		short: "r",
		long: "required",
		help: "A required option.",
		expected_value: ExpectsValue("str"),
		plurality: One,
		required: True,
	}
	defaulted_option = {
		short: "d",
		long: "defaulted",
		help: "A defaulted option.",
		expected_value: ExpectsValue("str"),
		plurality: One,
		required: False,
	}
	config = {
		name: "app",
		version: "",
		authors: [],
		description: "",
		options: [required_option, defaulted_option],
		parameters: [
			{ name: "input", help: "Input.", type: "str", plurality: One, required: True },
			{ name: "output", help: "Output.", type: "str", plurality: Optional, required: False },
			{ name: "rest", help: "Remaining.", type: "str", plurality: Many, required: False },
		],
		subcommands: NoSubcommands,
	}

	Help.usage_help(config, ["app"], Plain)
		== "Usage:\n  app -r/--required STR [OPTIONS] <input> [<output>] [<rest>...]"
}

help_test_subcommand : SubcommandConfig
help_test_subcommand = {
	description: "Run the task.",
	options: [],
	parameters: [],
	subcommands: NoSubcommands,
}

## Optional and required subcommands use distinct usage notation.
expect {
	base_config : CliConfig
	base_config = {
		name: "app",
		version: "",
		authors: [],
		description: "",
		options: [],
		parameters: [],
		subcommands: NoSubcommands,
	}
	commands : List((Str, SubcommandConfig))
	commands = [("run", help_test_subcommand)]

	optional_config : CliConfig
	optional_config = {
		name: base_config.name,
		version: base_config.version,
		authors: base_config.authors,
		description: base_config.description,
		options: base_config.options,
		parameters: base_config.parameters,
		subcommands: HasSubcommands({ commands, required: False }),
	}
	required_config : CliConfig
	required_config = {
		name: base_config.name,
		version: base_config.version,
		authors: base_config.authors,
		description: base_config.description,
		options: base_config.options,
		parameters: base_config.parameters,
		subcommands: HasSubcommands({ commands, required: True }),
	}
	optional_usage = Help.usage_help(optional_config, ["app"], Plain)
	required_usage = Help.usage_help(required_config, ["app"], Plain)

	Str.inspect((optional_usage, required_usage))
		==
		\\("Usage:\n  app [COMMAND]", "Usage:\n  app <COMMAND>")
}

## Command help preserves declaration order.
expect {
	commands_help(
		HasSubcommands({
			commands: [("z-last", help_test_subcommand), ("a-first", help_test_subcommand)],
			required: False,
		}),
		Plain,
	)
		== "Commands:\n  z-last   Run the task.\n  a-first  Run the task."
}

full_help_snapshot_config : CliConfig
full_help_snapshot_config = {
	name: "app",
	version: "v1.2.3",
	authors: ["A. Person <a@example.com>"],
	description: "A representative command.",
	options: [
		{
			short: "r",
			long: "required",
			help: "Required value.",
			expected_value: ExpectsValue("str"),
			plurality: One,
			required: True,
		},
		{
			short: "d",
			long: "defaulted",
			help: "Defaulted value.\nContinued explanation.",
			expected_value: ExpectsValue("str"),
			plurality: One,
			required: False,
		},
	],
	parameters: [
		{ name: "input", help: "Input file.", type: "str", plurality: One, required: True },
		{ name: "output", help: "Output file.", type: "str", plurality: Optional, required: False },
		{ name: "rest", help: "Remaining files.", type: "str", plurality: Many, required: False },
	],
	subcommands: HasSubcommands({
		commands: [
			("run", { ..help_test_subcommand, description: "Run the task." }),
			("build", { ..help_test_subcommand, description: "Build the task." }),
		],
		required: False,
	}),
}

## Full plain help is an exact golden covering layout, ordering, and wrapping.
expect {
	Help.help_text(full_help_snapshot_config, ["app"], Plain)
		==
		\\app v1.2.3
		\\A. Person <a@example.com>
		\\
		\\A representative command.
		\\
		\\Usage:
		\\  app -r/--required STR [OPTIONS] <input> [<output>] [<rest>...] [COMMAND]
		\\
		\\Commands:
		\\  run    Run the task.
		\\  build  Build the task.
		\\
		\\Arguments:
		\\  <input>    Input file.
		\\  <output>   Output file.
		\\  <rest...>  Remaining files.
		\\
		\\Options:
		\\  -r STR, --required STR   Required value.
		\\  -d STR, --defaulted STR  Defaulted value.
		\\                           Continued explanation.
}
