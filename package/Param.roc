import path.Path
import Base exposing [
	ArgExtractErr,
	DefaultableParameterConfigBaseParams,
	DefaultableParameterConfigParams,
	InvalidValue,
	ParameterConfig,
	ParameterConfigBaseParams,
	ParameterConfigParams,
	ValueParser,
	arg_to_bytes,
	num_type_name,
	str_type_name,
]
import Builder exposing [CliBuilder, GetParamsAction, StopCollectingAction]
import Extract exposing [extract_param_values]
import Parser exposing [ArgValue]

Param := [].{
	builder_with_parameter_parser : ParameterConfig, (List(Path) -> Try(data, ArgExtractErr)) -> CliBuilder(data, from_action, to_action)
	builder_with_parameter_parser = |param, value_parser| {
		arg_parser = |args| {
			{ values, remaining_args } = extract_param_values({ args, param })?
			data = value_parser(values)?

			Ok({ data, remaining_args })
		}

		Builder.add_parameter(Builder.from_arg_parser(arg_parser), param)
	}

	## Add a required parameter of a custom type.
	single : DefaultableParameterConfigParams(data) -> CliBuilder(data, { ..action }, GetParamsAction)
	single = |{ parser, type, name, help, default }| {
		param = { name, type, help, plurality: One }

		default_generator = |{}|
			match default {
				Value(default_value) => Ok(default_value)
				Generate(generator) => Ok(generator({}))
				NoDefault => Err(MissingParam(param))
			}

		value_parser = |values|
			match values {
				[] => default_generator({})
				[single_value, ..] =>
					match parser(single_value) {
						Ok(parsed) => Ok(parsed)
						Err(err) => Err(InvalidParamValue(err, param))
					}
				}

		Param.builder_with_parameter_parser(param, value_parser)
	}

	## Add an optional parameter of a custom type.
	maybe : ParameterConfigParams(data) -> CliBuilder(Try(data, [NoValue]), { ..action }, GetParamsAction)
	maybe = |{ parser, type, name, help }| {
		param = { name, type, help, plurality: Optional }

		value_parser = |values|
			match values {
				[] => Ok(Err(NoValue))
				[single_value, ..] =>
					match parser(single_value) {
						Ok(parsed) => Ok(Ok(parsed))
						Err(err) => Err(InvalidParamValue(err, param))
					}
				}

		Param.builder_with_parameter_parser(param, value_parser)
	}

	## Add a parameter that can be provided multiple times.
	list : ParameterConfigParams(data) -> CliBuilder(List(data), { ..action }, StopCollectingAction)
	list = |{ parser, type, name, help }| {
		param = { name, type, help, plurality: Many }

		value_parser = |values|
			parse_param_value_list(values, param, parser, [])

		Param.builder_with_parameter_parser(param, value_parser)
	}

	arg : DefaultableParameterConfigBaseParams(Path) -> CliBuilder(Path, { ..action }, GetParamsAction)
	arg = |params| Param.single(defaultable_parameter_params(params, str_type_name, |a| Ok(a)))

	maybe_arg : ParameterConfigBaseParams -> CliBuilder(ArgValue, { ..action }, GetParamsAction)
	maybe_arg = |params| Param.maybe(parameter_params(params, str_type_name, |a| Ok(a)))

	arg_list : ParameterConfigBaseParams -> CliBuilder(List(Path), { ..action }, StopCollectingAction)
	arg_list = |params| Param.list(parameter_params(params, str_type_name, |a| Ok(a)))

	bytes : DefaultableParameterConfigBaseParams(List(U8)) -> CliBuilder(List(U8), { ..action }, GetParamsAction)
	bytes = |params| Param.single(defaultable_parameter_params(params, str_type_name, |a| Ok(arg_to_bytes(a))))

	maybe_bytes : ParameterConfigBaseParams -> CliBuilder(Try(List(U8), [NoValue]), { ..action }, GetParamsAction)
	maybe_bytes = |params| Param.maybe(parameter_params(params, str_type_name, |a| Ok(arg_to_bytes(a))))

	bytes_list : ParameterConfigBaseParams -> CliBuilder(List(List(U8)), { ..action }, StopCollectingAction)
	bytes_list = |params| Param.list(parameter_params(params, str_type_name, |a| Ok(arg_to_bytes(a))))

	str : DefaultableParameterConfigBaseParams(Str) -> CliBuilder(Str, { ..action }, GetParamsAction)
	str = |params| Param.single(defaultable_parameter_params(params, str_type_name, parse_str_arg))

	maybe_str : ParameterConfigBaseParams -> CliBuilder(Try(Str, [NoValue]), { ..action }, GetParamsAction)
	maybe_str = |params| Param.maybe(parameter_params(params, str_type_name, parse_str_arg))

	str_list : ParameterConfigBaseParams -> CliBuilder(List(Str), { ..action }, StopCollectingAction)
	str_list = |params| Param.list(parameter_params(params, str_type_name, parse_str_arg))

	dec : DefaultableParameterConfigBaseParams(Dec) -> CliBuilder(Dec, { ..action }, GetParamsAction)
	dec = |params| Param.number_single(params, Dec.from_str)

	maybe_dec : ParameterConfigBaseParams -> CliBuilder(Try(Dec, [NoValue]), { ..action }, GetParamsAction)
	maybe_dec = |params| Param.number_maybe(params, Dec.from_str)

	dec_list : ParameterConfigBaseParams -> CliBuilder(List(Dec), { ..action }, StopCollectingAction)
	dec_list = |params| Param.number_list(params, Dec.from_str)

	f32 : DefaultableParameterConfigBaseParams(F32) -> CliBuilder(F32, { ..action }, GetParamsAction)
	f32 = |params| Param.number_single(params, F32.from_str)

	maybe_f32 : ParameterConfigBaseParams -> CliBuilder(Try(F32, [NoValue]), { ..action }, GetParamsAction)
	maybe_f32 = |params| Param.number_maybe(params, F32.from_str)

	f32_list : ParameterConfigBaseParams -> CliBuilder(List(F32), { ..action }, StopCollectingAction)
	f32_list = |params| Param.number_list(params, F32.from_str)

	f64 : DefaultableParameterConfigBaseParams(F64) -> CliBuilder(F64, { ..action }, GetParamsAction)
	f64 = |params| Param.number_single(params, F64.from_str)

	maybe_f64 : ParameterConfigBaseParams -> CliBuilder(Try(F64, [NoValue]), { ..action }, GetParamsAction)
	maybe_f64 = |params| Param.number_maybe(params, F64.from_str)

	f64_list : ParameterConfigBaseParams -> CliBuilder(List(F64), { ..action }, StopCollectingAction)
	f64_list = |params| Param.number_list(params, F64.from_str)

	u8 : DefaultableParameterConfigBaseParams(U8) -> CliBuilder(U8, { ..action }, GetParamsAction)
	u8 = |params| Param.number_single(params, U8.from_str)

	maybe_u8 : ParameterConfigBaseParams -> CliBuilder(Try(U8, [NoValue]), { ..action }, GetParamsAction)
	maybe_u8 = |params| Param.number_maybe(params, U8.from_str)

	u8_list : ParameterConfigBaseParams -> CliBuilder(List(U8), { ..action }, StopCollectingAction)
	u8_list = |params| Param.number_list(params, U8.from_str)

	u16 : DefaultableParameterConfigBaseParams(U16) -> CliBuilder(U16, { ..action }, GetParamsAction)
	u16 = |params| Param.number_single(params, U16.from_str)

	maybe_u16 : ParameterConfigBaseParams -> CliBuilder(Try(U16, [NoValue]), { ..action }, GetParamsAction)
	maybe_u16 = |params| Param.number_maybe(params, U16.from_str)

	u16_list : ParameterConfigBaseParams -> CliBuilder(List(U16), { ..action }, StopCollectingAction)
	u16_list = |params| Param.number_list(params, U16.from_str)

	u32 : DefaultableParameterConfigBaseParams(U32) -> CliBuilder(U32, { ..action }, GetParamsAction)
	u32 = |params| Param.number_single(params, U32.from_str)

	maybe_u32 : ParameterConfigBaseParams -> CliBuilder(Try(U32, [NoValue]), { ..action }, GetParamsAction)
	maybe_u32 = |params| Param.number_maybe(params, U32.from_str)

	u32_list : ParameterConfigBaseParams -> CliBuilder(List(U32), { ..action }, StopCollectingAction)
	u32_list = |params| Param.number_list(params, U32.from_str)

	u64 : DefaultableParameterConfigBaseParams(U64) -> CliBuilder(U64, { ..action }, GetParamsAction)
	u64 = |params| Param.number_single(params, U64.from_str)

	maybe_u64 : ParameterConfigBaseParams -> CliBuilder(Try(U64, [NoValue]), { ..action }, GetParamsAction)
	maybe_u64 = |params| Param.number_maybe(params, U64.from_str)

	u64_list : ParameterConfigBaseParams -> CliBuilder(List(U64), { ..action }, StopCollectingAction)
	u64_list = |params| Param.number_list(params, U64.from_str)

	u128 : DefaultableParameterConfigBaseParams(U128) -> CliBuilder(U128, { ..action }, GetParamsAction)
	u128 = |params| Param.number_single(params, U128.from_str)

	maybe_u128 : ParameterConfigBaseParams -> CliBuilder(Try(U128, [NoValue]), { ..action }, GetParamsAction)
	maybe_u128 = |params| Param.number_maybe(params, U128.from_str)

	u128_list : ParameterConfigBaseParams -> CliBuilder(List(U128), { ..action }, StopCollectingAction)
	u128_list = |params| Param.number_list(params, U128.from_str)

	i8 : DefaultableParameterConfigBaseParams(I8) -> CliBuilder(I8, { ..action }, GetParamsAction)
	i8 = |params| Param.number_single(params, I8.from_str)

	maybe_i8 : ParameterConfigBaseParams -> CliBuilder(Try(I8, [NoValue]), { ..action }, GetParamsAction)
	maybe_i8 = |params| Param.number_maybe(params, I8.from_str)

	i8_list : ParameterConfigBaseParams -> CliBuilder(List(I8), { ..action }, StopCollectingAction)
	i8_list = |params| Param.number_list(params, I8.from_str)

	i16 : DefaultableParameterConfigBaseParams(I16) -> CliBuilder(I16, { ..action }, GetParamsAction)
	i16 = |params| Param.number_single(params, I16.from_str)

	maybe_i16 : ParameterConfigBaseParams -> CliBuilder(Try(I16, [NoValue]), { ..action }, GetParamsAction)
	maybe_i16 = |params| Param.number_maybe(params, I16.from_str)

	i16_list : ParameterConfigBaseParams -> CliBuilder(List(I16), { ..action }, StopCollectingAction)
	i16_list = |params| Param.number_list(params, I16.from_str)

	i32 : DefaultableParameterConfigBaseParams(I32) -> CliBuilder(I32, { ..action }, GetParamsAction)
	i32 = |params| Param.number_single(params, I32.from_str)

	maybe_i32 : ParameterConfigBaseParams -> CliBuilder(Try(I32, [NoValue]), { ..action }, GetParamsAction)
	maybe_i32 = |params| Param.number_maybe(params, I32.from_str)

	i32_list : ParameterConfigBaseParams -> CliBuilder(List(I32), { ..action }, StopCollectingAction)
	i32_list = |params| Param.number_list(params, I32.from_str)

	i64 : DefaultableParameterConfigBaseParams(I64) -> CliBuilder(I64, { ..action }, GetParamsAction)
	i64 = |params| Param.number_single(params, I64.from_str)

	maybe_i64 : ParameterConfigBaseParams -> CliBuilder(Try(I64, [NoValue]), { ..action }, GetParamsAction)
	maybe_i64 = |params| Param.number_maybe(params, I64.from_str)

	i64_list : ParameterConfigBaseParams -> CliBuilder(List(I64), { ..action }, StopCollectingAction)
	i64_list = |params| Param.number_list(params, I64.from_str)

	i128 : DefaultableParameterConfigBaseParams(I128) -> CliBuilder(I128, { ..action }, GetParamsAction)
	i128 = |params| Param.number_single(params, I128.from_str)

	maybe_i128 : ParameterConfigBaseParams -> CliBuilder(Try(I128, [NoValue]), { ..action }, GetParamsAction)
	maybe_i128 = |params| Param.number_maybe(params, I128.from_str)

	i128_list : ParameterConfigBaseParams -> CliBuilder(List(I128), { ..action }, StopCollectingAction)
	i128_list = |params| Param.number_list(params, I128.from_str)

	number_single : DefaultableParameterConfigBaseParams(a), (Str -> Try(a, _)) -> CliBuilder(a, { ..action }, GetParamsAction)
	number_single = |params, parser|
		Param.single(defaultable_parameter_params(params, num_type_name, |value_arg| parse_number_arg(value_arg, parser)))

	number_maybe : ParameterConfigBaseParams, (Str -> Try(a, _)) -> CliBuilder(Try(a, [NoValue]), { ..action }, GetParamsAction)
	number_maybe = |params, parser|
		Param.maybe(parameter_params(params, num_type_name, |value_arg| parse_number_arg(value_arg, parser)))

	number_list : ParameterConfigBaseParams, (Str -> Try(a, _)) -> CliBuilder(List(a), { ..action }, StopCollectingAction)
	number_list = |params, parser|
		Param.list(parameter_params(params, num_type_name, |value_arg| parse_number_arg(value_arg, parser)))
}

defaultable_parameter_params : DefaultableParameterConfigBaseParams(a), Str, ValueParser(a) -> DefaultableParameterConfigParams(a)
defaultable_parameter_params = |{ name, help, default }, type_name, parser| {
	name,
	help,
	default,
	type: type_name,
	parser,
}

parameter_params : ParameterConfigBaseParams, Str, ValueParser(a) -> ParameterConfigParams(a)
parameter_params = |{ name, help }, type_name, parser| {
	name,
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

parse_param_value_list : List(Path), ParameterConfig, ValueParser(a), List(a) -> Try(List(a), ArgExtractErr)
parse_param_value_list = |values, param, parser, out|
	match values {
		[] => Ok(out)
		[arg, .. as rest] =>
			match parser(arg) {
				Ok(parsed) => parse_param_value_list(rest, param, parser, out.append(parsed))
				Err(err) => Err(InvalidParamValue(err, param))
			}
		}
