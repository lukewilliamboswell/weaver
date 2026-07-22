import path.Path
import Base exposing [
	ArgExtractErr,
	ArgParserResult,
	DefaultableOptionConfigBaseParams,
	DefaultableOptionConfigParams,
	InvalidValue,
	OptionConfig,
	OptionConfigBaseParams,
	OptionConfigParams,
	ValueParser,
	arg_to_bytes,
	num_type_name,
	str_type_name,
]
import Builder exposing [CliBuilder, GetOptionsAction]
import Extract exposing [extract_option_values]
import Parser exposing [ArgValue]

## Options that your CLI will parse as fields in your config.
Opt := [].{
	builder_with_option_parser : OptionConfig, (List(ArgValue) -> Try(data, ArgExtractErr)) -> CliBuilder(data, GetOptionsAction, GetOptionsAction)
	builder_with_option_parser = |option, value_parser| {
		arg_parser = |args| {
			{ values, remaining_args } = extract_option_values({ args, option })?
			data = value_parser(values)?

			Ok({ data, remaining_args })
		}

		Builder.add_option(Builder.from_arg_parser(arg_parser), option)
	}

	get_maybe_value : List(ArgValue), OptionConfig -> Try(Try(ArgValue, [NoValue]), ArgExtractErr)
	get_maybe_value = |values, option|
		match values {
			[] => Ok(Err(NoValue))
			[single_value] => Ok(Ok(single_value))
			[_, ..] => Err(OptionCanOnlyBeSetOnce(option))
		}

	## Add a required option that takes a custom type.
	single : DefaultableOptionConfigParams(a) -> CliBuilder(a, GetOptionsAction, GetOptionsAction)
	single = |{ parser, type, short, long, help, default }| {
		required =
			match default {
				NoDefault => True
				Value(_) | Generate(_) => False
			}

		option = { expected_value: ExpectsValue(type), plurality: One, required, short, long, help }

		default_generator = |{}|
			match default {
				Value(default_value) => Ok(default_value)
				Generate(generator) => Ok(generator({}))
				NoDefault => Err(MissingOption(option))
			}

		value_parser = |values| {
			value = Opt.get_maybe_value(values, option)?

			match value {
				Err(NoValue) => default_generator({})
				Ok(Err(NoValue)) => Err(NoValueProvidedForOption(option))
				Ok(Ok(val)) =>
					match parser(val) {
						Ok(parsed) => Ok(parsed)
						Err(err) => Err(InvalidOptionValue(err, option))
					}
				}
		}

		Opt.builder_with_option_parser(option, value_parser)
	}

	## Add an optional option that takes a custom type.
	maybe : OptionConfigParams(data) -> CliBuilder(Try(data, [NoValue]), GetOptionsAction, GetOptionsAction)
	maybe = |{ parser, type, short, long, help }| {
		option = { expected_value: ExpectsValue(type), plurality: Optional, required: False, short, long, help }

		value_parser = |values| {
			value = Opt.get_maybe_value(values, option)?

			match value {
				Err(NoValue) => Ok(Err(NoValue))
				Ok(Err(NoValue)) => Err(NoValueProvidedForOption(option))
				Ok(Ok(val)) =>
					match parser(val) {
						Ok(parsed) => Ok(Ok(parsed))
						Err(err) => Err(InvalidOptionValue(err, option))
					}
				}
		}

		Opt.builder_with_option_parser(option, value_parser)
	}

	## Add an option that takes a custom type and can be given multiple times.
	list : OptionConfigParams(data) -> CliBuilder(List(data), GetOptionsAction, GetOptionsAction)
	list = |{ parser, type, short, long, help }| {
		option = { expected_value: ExpectsValue(type), plurality: Many, required: False, short, long, help }

		value_parser = |values|
			parse_option_value_list(values, option, parser, [])

		Opt.builder_with_option_parser(option, value_parser)
	}

	## Add an optional flag.
	flag : OptionConfigBaseParams -> CliBuilder(Bool, GetOptionsAction, GetOptionsAction)
	flag = |{ short, long, help }| {
		option = { expected_value: NothingExpected, plurality: Optional, required: False, short, long, help }

		value_parser = |values| {
			value = Opt.get_maybe_value(values, option)?

			match value {
				Err(NoValue) => Ok(False)
				Ok(Err(NoValue)) => Ok(True)
				Ok(Ok(_)) => Err(OptionDoesNotExpectValue(option))
			}
		}

		Opt.builder_with_option_parser(option, value_parser)
	}

	## Add a flag that can be given multiple times.
	count : OptionConfigBaseParams -> CliBuilder(U64, GetOptionsAction, GetOptionsAction)
	count = |{ short, long, help }| {
		option = { expected_value: NothingExpected, plurality: Many, required: False, short, long, help }

		value_parser = |values|
			if values.any(
				|value|
					match value {
						Ok(_) => True
						Err(NoValue) => False
					},
			) {
				Err(OptionDoesNotExpectValue(option))
			} else {
				Ok(values.len())
			}

		Opt.builder_with_option_parser(option, value_parser)
	}

	arg : DefaultableOptionConfigBaseParams(Path) -> CliBuilder(Path, GetOptionsAction, GetOptionsAction)
	arg = |params| Opt.single(defaultable_option_params(params, str_type_name, |a| Ok(a)))

	maybe_arg : OptionConfigBaseParams -> CliBuilder(Try(Path, [NoValue]), GetOptionsAction, GetOptionsAction)
	maybe_arg = |params| Opt.maybe(option_params(params, str_type_name, |a| Ok(a)))

	arg_list : OptionConfigBaseParams -> CliBuilder(List(Path), GetOptionsAction, GetOptionsAction)
	arg_list = |params| Opt.list(option_params(params, str_type_name, |a| Ok(a)))

	bytes : DefaultableOptionConfigBaseParams(List(U8)) -> CliBuilder(List(U8), GetOptionsAction, GetOptionsAction)
	bytes = |params| Opt.single(defaultable_option_params(params, str_type_name, |a| Ok(arg_to_bytes(a))))

	maybe_bytes : OptionConfigBaseParams -> CliBuilder(Try(List(U8), [NoValue]), GetOptionsAction, GetOptionsAction)
	maybe_bytes = |params| Opt.maybe(option_params(params, str_type_name, |a| Ok(arg_to_bytes(a))))

	bytes_list : OptionConfigBaseParams -> CliBuilder(List(List(U8)), GetOptionsAction, GetOptionsAction)
	bytes_list = |params| Opt.list(option_params(params, str_type_name, |a| Ok(arg_to_bytes(a))))

	str : DefaultableOptionConfigBaseParams(Str) -> CliBuilder(Str, GetOptionsAction, GetOptionsAction)
	str = |params| Opt.single(defaultable_option_params(params, str_type_name, parse_str_arg))

	maybe_str : OptionConfigBaseParams -> CliBuilder(Try(Str, [NoValue]), GetOptionsAction, GetOptionsAction)
	maybe_str = |params| Opt.maybe(option_params(params, str_type_name, parse_str_arg))

	str_list : OptionConfigBaseParams -> CliBuilder(List(Str), GetOptionsAction, GetOptionsAction)
	str_list = |params| Opt.list(option_params(params, str_type_name, parse_str_arg))

	dec : DefaultableOptionConfigBaseParams(Dec) -> CliBuilder(Dec, GetOptionsAction, GetOptionsAction)
	dec = |params| Opt.number_single(params, Dec.from_str)

	maybe_dec : OptionConfigBaseParams -> CliBuilder(Try(Dec, [NoValue]), GetOptionsAction, GetOptionsAction)
	maybe_dec = |params| Opt.number_maybe(params, Dec.from_str)

	dec_list : OptionConfigBaseParams -> CliBuilder(List(Dec), GetOptionsAction, GetOptionsAction)
	dec_list = |params| Opt.number_list(params, Dec.from_str)

	f32 : DefaultableOptionConfigBaseParams(F32) -> CliBuilder(F32, GetOptionsAction, GetOptionsAction)
	f32 = |params| Opt.number_single(params, F32.from_str)

	maybe_f32 : OptionConfigBaseParams -> CliBuilder(Try(F32, [NoValue]), GetOptionsAction, GetOptionsAction)
	maybe_f32 = |params| Opt.number_maybe(params, F32.from_str)

	f32_list : OptionConfigBaseParams -> CliBuilder(List(F32), GetOptionsAction, GetOptionsAction)
	f32_list = |params| Opt.number_list(params, F32.from_str)

	f64 : DefaultableOptionConfigBaseParams(F64) -> CliBuilder(F64, GetOptionsAction, GetOptionsAction)
	f64 = |params| Opt.number_single(params, F64.from_str)

	maybe_f64 : OptionConfigBaseParams -> CliBuilder(Try(F64, [NoValue]), GetOptionsAction, GetOptionsAction)
	maybe_f64 = |params| Opt.number_maybe(params, F64.from_str)

	f64_list : OptionConfigBaseParams -> CliBuilder(List(F64), GetOptionsAction, GetOptionsAction)
	f64_list = |params| Opt.number_list(params, F64.from_str)

	u8 : DefaultableOptionConfigBaseParams(U8) -> CliBuilder(U8, GetOptionsAction, GetOptionsAction)
	u8 = |params| Opt.number_single(params, U8.from_str)

	maybe_u8 : OptionConfigBaseParams -> CliBuilder(Try(U8, [NoValue]), GetOptionsAction, GetOptionsAction)
	maybe_u8 = |params| Opt.number_maybe(params, U8.from_str)

	u8_list : OptionConfigBaseParams -> CliBuilder(List(U8), GetOptionsAction, GetOptionsAction)
	u8_list = |params| Opt.number_list(params, U8.from_str)

	u16 : DefaultableOptionConfigBaseParams(U16) -> CliBuilder(U16, GetOptionsAction, GetOptionsAction)
	u16 = |params| Opt.number_single(params, U16.from_str)

	maybe_u16 : OptionConfigBaseParams -> CliBuilder(Try(U16, [NoValue]), GetOptionsAction, GetOptionsAction)
	maybe_u16 = |params| Opt.number_maybe(params, U16.from_str)

	u16_list : OptionConfigBaseParams -> CliBuilder(List(U16), GetOptionsAction, GetOptionsAction)
	u16_list = |params| Opt.number_list(params, U16.from_str)

	u32 : DefaultableOptionConfigBaseParams(U32) -> CliBuilder(U32, GetOptionsAction, GetOptionsAction)
	u32 = |params| Opt.number_single(params, U32.from_str)

	maybe_u32 : OptionConfigBaseParams -> CliBuilder(Try(U32, [NoValue]), GetOptionsAction, GetOptionsAction)
	maybe_u32 = |params| Opt.number_maybe(params, U32.from_str)

	u32_list : OptionConfigBaseParams -> CliBuilder(List(U32), GetOptionsAction, GetOptionsAction)
	u32_list = |params| Opt.number_list(params, U32.from_str)

	u64 : DefaultableOptionConfigBaseParams(U64) -> CliBuilder(U64, GetOptionsAction, GetOptionsAction)
	u64 = |params| Opt.number_single(params, U64.from_str)

	maybe_u64 : OptionConfigBaseParams -> CliBuilder(Try(U64, [NoValue]), GetOptionsAction, GetOptionsAction)
	maybe_u64 = |params| Opt.number_maybe(params, U64.from_str)

	u64_list : OptionConfigBaseParams -> CliBuilder(List(U64), GetOptionsAction, GetOptionsAction)
	u64_list = |params| Opt.number_list(params, U64.from_str)

	u128 : DefaultableOptionConfigBaseParams(U128) -> CliBuilder(U128, GetOptionsAction, GetOptionsAction)
	u128 = |params| Opt.number_single(params, U128.from_str)

	maybe_u128 : OptionConfigBaseParams -> CliBuilder(Try(U128, [NoValue]), GetOptionsAction, GetOptionsAction)
	maybe_u128 = |params| Opt.number_maybe(params, U128.from_str)

	u128_list : OptionConfigBaseParams -> CliBuilder(List(U128), GetOptionsAction, GetOptionsAction)
	u128_list = |params| Opt.number_list(params, U128.from_str)

	i8 : DefaultableOptionConfigBaseParams(I8) -> CliBuilder(I8, GetOptionsAction, GetOptionsAction)
	i8 = |params| Opt.number_single(params, I8.from_str)

	maybe_i8 : OptionConfigBaseParams -> CliBuilder(Try(I8, [NoValue]), GetOptionsAction, GetOptionsAction)
	maybe_i8 = |params| Opt.number_maybe(params, I8.from_str)

	i8_list : OptionConfigBaseParams -> CliBuilder(List(I8), GetOptionsAction, GetOptionsAction)
	i8_list = |params| Opt.number_list(params, I8.from_str)

	i16 : DefaultableOptionConfigBaseParams(I16) -> CliBuilder(I16, GetOptionsAction, GetOptionsAction)
	i16 = |params| Opt.number_single(params, I16.from_str)

	maybe_i16 : OptionConfigBaseParams -> CliBuilder(Try(I16, [NoValue]), GetOptionsAction, GetOptionsAction)
	maybe_i16 = |params| Opt.number_maybe(params, I16.from_str)

	i16_list : OptionConfigBaseParams -> CliBuilder(List(I16), GetOptionsAction, GetOptionsAction)
	i16_list = |params| Opt.number_list(params, I16.from_str)

	i32 : DefaultableOptionConfigBaseParams(I32) -> CliBuilder(I32, GetOptionsAction, GetOptionsAction)
	i32 = |params| Opt.number_single(params, I32.from_str)

	maybe_i32 : OptionConfigBaseParams -> CliBuilder(Try(I32, [NoValue]), GetOptionsAction, GetOptionsAction)
	maybe_i32 = |params| Opt.number_maybe(params, I32.from_str)

	i32_list : OptionConfigBaseParams -> CliBuilder(List(I32), GetOptionsAction, GetOptionsAction)
	i32_list = |params| Opt.number_list(params, I32.from_str)

	i64 : DefaultableOptionConfigBaseParams(I64) -> CliBuilder(I64, GetOptionsAction, GetOptionsAction)
	i64 = |params| Opt.number_single(params, I64.from_str)

	maybe_i64 : OptionConfigBaseParams -> CliBuilder(Try(I64, [NoValue]), GetOptionsAction, GetOptionsAction)
	maybe_i64 = |params| Opt.number_maybe(params, I64.from_str)

	i64_list : OptionConfigBaseParams -> CliBuilder(List(I64), GetOptionsAction, GetOptionsAction)
	i64_list = |params| Opt.number_list(params, I64.from_str)

	i128 : DefaultableOptionConfigBaseParams(I128) -> CliBuilder(I128, GetOptionsAction, GetOptionsAction)
	i128 = |params| Opt.number_single(params, I128.from_str)

	maybe_i128 : OptionConfigBaseParams -> CliBuilder(Try(I128, [NoValue]), GetOptionsAction, GetOptionsAction)
	maybe_i128 = |params| Opt.number_maybe(params, I128.from_str)

	i128_list : OptionConfigBaseParams -> CliBuilder(List(I128), GetOptionsAction, GetOptionsAction)
	i128_list = |params| Opt.number_list(params, I128.from_str)

	number_single : DefaultableOptionConfigBaseParams(a), (Str -> Try(a, _)) -> CliBuilder(a, GetOptionsAction, GetOptionsAction)
	number_single = |params, parser|
		Opt.single(defaultable_option_params(params, num_type_name, |value_arg| parse_number_arg(value_arg, parser)))

	number_maybe : OptionConfigBaseParams, (Str -> Try(a, _)) -> CliBuilder(Try(a, [NoValue]), GetOptionsAction, GetOptionsAction)
	number_maybe = |params, parser|
		Opt.maybe(option_params(params, num_type_name, |value_arg| parse_number_arg(value_arg, parser)))

	number_list : OptionConfigBaseParams, (Str -> Try(a, _)) -> CliBuilder(List(a), GetOptionsAction, GetOptionsAction)
	number_list = |params, parser|
		Opt.list(option_params(params, num_type_name, |value_arg| parse_number_arg(value_arg, parser)))
}

defaultable_option_params : DefaultableOptionConfigBaseParams(a), Str, ValueParser(a) -> DefaultableOptionConfigParams(a)
defaultable_option_params = |{ short, long, help, default }, type_name, parser| {
	short,
	long,
	help,
	default,
	type: type_name,
	parser,
}

option_params : OptionConfigBaseParams, Str, ValueParser(a) -> OptionConfigParams(a)
option_params = |{ short, long, help }, type_name, parser| {
	short,
	long,
	help,
	type: type_name,
	parser,
}

parse_str_arg : Path -> Try(Str, InvalidValue)
parse_str_arg = |arg|
	match Path.to_str(arg) {
		Ok(str) => Ok(str)
		Err(_) => Err(InvalidUtf8)
	}

parse_number_arg : Path, (Str -> Try(a, _)) -> Try(a, InvalidValue)
parse_number_arg = |arg, parser| {
	str = parse_str_arg(arg)?

	match parser(str) {
		Ok(value) => Ok(value)
		Err(_) => Err(InvalidNumStr)
	}
}

parse_option_value_list : List(ArgValue), OptionConfig, ValueParser(a), List(a) -> Try(List(a), ArgExtractErr)
parse_option_value_list = |values, option, parser, out|
	match values {
		[] => Ok(out)
		[value, .. as rest] =>
			match value {
				Err(NoValue) => Err(NoValueProvidedForOption(option))
				Ok(arg) =>
					match parser(arg) {
						Ok(parsed) => parse_option_value_list(rest, option, parser, out.append(parsed))
						Err(err) => Err(InvalidOptionValue(err, option))
					}
				}
		}

## Count options include every occurrence inside one grouped token.
expect {
	{ parser, .. } =
		Builder.into_parts(
			Opt.count({ short: "v", long: "verbose", help: "Increase verbosity." }),
		)

	parser({
		args: [ShortGroup({ names: ["v", "v", "v"], complete: Complete })],
		subcommand_path: ["app"],
	})
		== ArgParserResult.SuccessfullyParsed({
			data: 3,
			remaining_args: [],
			subcommand_path: ["app"],
		})
}

## Repeating an ordinary flag inside one group reports a duplicate.
expect {
	params = { short: "f", long: "force", help: "Force the operation." }
	option = {
		short: params.short,
		long: params.long,
		help: params.help,
		expected_value: NothingExpected,
		plurality: Optional,
		required: False,
	}
	{ parser, .. } = Builder.into_parts(Opt.flag(params))

	parser({
		args: [ShortGroup({ names: ["f", "f"], complete: Complete })],
		subcommand_path: ["app"],
	})
		== ArgParserResult.IncorrectUsage(OptionCanOnlyBeSetOnce(option), { subcommand_path: ["app"] })
}

## Raw option parsers preserve an attached non-UTF-8 Unix value end to end.
expect {
	value = Path.from_raw(UnixBytes([0xFF, 0x80]))
	{ parser, .. } =
		Builder.into_parts(
			Opt.arg({
				short: "",
				long: "file",
				help: "Select a file.",
				default: NoDefault,
			}),
		)

	parser({
		args: [Long({ name: "file", value: Ok(value) })],
		subcommand_path: ["app"],
	})
		== ArgParserResult.SuccessfullyParsed({
			data: value,
			remaining_args: [],
			subcommand_path: ["app"],
		})
}
