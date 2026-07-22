## An OS-aware representation of a command-line argument.
##
## Though we tend to think of args as Unicode strings, Unix represents
## command-line arguments as bytes that are not necessarily UTF-8. Windows uses
## UTF-16 code units. Weaver keeps that platform boundary explicit: string
## parsers opt in to decoding, and future path parsers can opt in to
## path-specific semantics.
Arg := [Unix(List(U8)), Windows(List(U16))].{
	is_eq : _

	to_inspect : Arg -> Str
	to_inspect = |arg| Str.inspect(display(arg))

	## Wrap a raw, OS-aware numeric list into an `Arg`.
	from_raw_arg : [Unix(List(U8)), Windows(List(U16))] -> Arg
	from_raw_arg = |raw_arg|
		match raw_arg {
			Unix(bytes) => Unix(bytes)
			Windows(code_units) => Windows(code_units)
		}

	## Unwrap an `Arg` into a raw, OS-aware numeric list.
	to_raw_arg : Arg -> [Unix(List(U8)), Windows(List(U16))]
	to_raw_arg = |arg|
		match arg {
			Unix(bytes) => Unix(bytes)
			Windows(code_units) => Windows(code_units)
		}

	## Encode a UTF-8 `Str` to a Unix-flavored `Arg`.
	from_str : Str -> Arg
	from_str = |str| Unix(Str.to_utf8(str))

	## Attempt to decode an `Arg` to a `Str`.
	to_str : Arg -> Try(Str, [InvalidUtf8])
	to_str = |arg|
		match arg {
			Unix(bytes) =>
				match Str.from_utf8(bytes) {
					Ok(str) => Ok(str)
					Err(_) => Err(InvalidUtf8)
				}

			Windows(_) => Err(InvalidUtf8)
		}

	## Convert an `Arg` to raw bytes.
	to_bytes : Arg -> List(U8)
	to_bytes = |arg|
		match arg {
			Unix(bytes) => bytes
			Windows(code_units) =>
				code_units.fold(
					[],
					|bytes, code_unit| {
						upper = U64.to_u8_wrap(U16.to_u64(code_unit / 256))
						lower = U64.to_u8_wrap(U16.to_u64(code_unit % 256))

						bytes.append(upper).append(lower)
					},
				)
			}

	## Convert an Arg to a `Str` for display purposes.
	##
	## This replaces invalid codepoints with the Unicode replacement character.
	display : Arg -> Str
	display = |arg|
		match arg {
			Unix(bytes) => Str.from_utf8_lossy(bytes)
			Windows(code_units) => {
				display_bytes = 
					code_units.fold(
						[],
						|bytes, code_unit| {
							byte = 
								if code_unit <= 127 {
									U64.to_u8_wrap(U16.to_u64(code_unit))
								} else {
									'?'
								}

							bytes.append(byte)
						},
					)

				Str.from_utf8_lossy(display_bytes)
			}
		}
}
