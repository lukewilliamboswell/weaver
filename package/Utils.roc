Utils := [].{
	is_kebab_case : Str -> Bool
	is_kebab_case = |s| {
		dash_ascii_code : U8
		dash_ascii_code = 45

		bytes = Str.to_utf8(s)

		match bytes {
			[] => False
			[single] => is_digit(single) or is_lower_case(single)
			[first, .. as middle, last] => {
				first_is_kebab = is_lower_case(first)
				last_is_kebab = is_lower_case(last) or is_digit(last)

				middle_is_kebab =
					middle.all(
						|char|
							is_lower_case(char) or is_digit(char) or char == dash_ascii_code,
					)

				no_double_dashes =
					middle
						.map2(middle.drop_first(1), |left, right| (left, right))
						.all(
							|(left, right)|
								!(left == dash_ascii_code and right == dash_ascii_code),
						)

				first_is_kebab and last_is_kebab and middle_is_kebab and no_double_dashes
			}
		}
	}

	to_upper_case : Str -> Str
	to_upper_case = |str| {
		bytes =
			str
				.to_utf8()
				.map(
					|byte|
						if is_lower_case(byte) {
							byte - ('a' - 'A')
						} else {
							byte
						},
				)

		match Str.from_utf8(bytes) {
			Ok(out) => out
			Err(_) => ""
		}
	}

	## Split text into its Unicode scalar values, each as its own string.
	scalars : Str -> List(Str)
	scalars = |str|
		str
			.to_utf8()
			.fold(
				[],
				|chunks, byte|
					match chunks.last() {
						Ok(last) if is_continuation_byte(byte) => chunks.drop_last(1).append(last.append(byte))
						_ => chunks.append([byte])
					},
			)
			.map(|chunk| Str.from_utf8(chunk) ?? replacement_character)

	## Quote text that came from the command line so it can be shown in a
	## terminal message. The result reads like a Roc string literal: quotes and
	## backslashes are escaped, and so is every control character, so argument
	## text can never emit escape sequences or reshape the message.
	quote : Str -> Str
	quote = |str| {
		escaped =
			Utils.scalars(str)
				.map(
					|scalar|
						if scalar == "\"" {
							"\\\""
						} else if scalar == "\\" {
							"\\\\"
						} else {
							escape_control(scalar)
						},
				)

		"\"${Str.join_with(escaped, "")}\""
	}

	## Escape every control character in text without quoting it, for text
	## such as a value parser's reason that may embed argument text.
	escape_controls : Str -> Str
	escape_controls = |str|
		Str.join_with(Utils.scalars(str).map(escape_control), "")
}

replacement_character : Str
replacement_character = "\u(FFFD)"

is_continuation_byte : U8 -> Bool
is_continuation_byte = |byte|
	byte >= 0x80 and byte < 0xC0

## The code point of a string holding one Unicode scalar value.
code_point : Str -> U32
code_point = |scalar|
	match Str.to_utf8(scalar) {
		[a] => U8.to_u32(a)
		[a, b] => (U8.to_u32(a) % 32) * 64 + (U8.to_u32(b) % 64)
		[a, b, c] => (U8.to_u32(a) % 16) * 4096 + (U8.to_u32(b) % 64) * 64 + (U8.to_u32(c) % 64)
		[a, b, c, d] => (U8.to_u32(a) % 8) * 262144 + (U8.to_u32(b) % 64) * 4096 + (U8.to_u32(c) % 64) * 64 + (U8.to_u32(d) % 64)
		_ => 0xFFFD
	}

## C0 and C1 controls and DEL, plus the invisible characters that reorder or
## break displayed text: bidirectional marks, embeddings, overrides and
## isolates, the line and paragraph separators, and the byte order mark.
is_control : U32 -> Bool
is_control = |cp|
	cp < 0x20
		or (cp >= 0x7F and cp <= 0x9F)
		or cp == 0x061C
		or cp == 0x200E
		or cp == 0x200F
		or (cp >= 0x2028 and cp <= 0x202E)
		or (cp >= 0x2066 and cp <= 0x2069)
		or cp == 0xFEFF

escape_control : Str -> Str
escape_control = |scalar| {
	cp = code_point(scalar)

	if !is_control(cp) {
		scalar
	} else if cp == 0x0A {
		"\\n"
	} else if cp == 0x0D {
		"\\r"
	} else if cp == 0x09 {
		"\\t"
	} else {
		"\\u(${to_hex(cp)})"
	}
}

to_hex : U32 -> Str
to_hex = |n| {
	digits = Str.to_utf8("0123456789abcdef")
	digit = digits.get(U32.to_u64(n % 16)) ?? '0'
	rest =
		if n < 16 {
			""
		} else {
			to_hex(n // 16)
		}

	"${rest}${Str.from_utf8([digit]) ?? ""}"
}

## Multibyte characters stay whole when text is split into scalar values.
expect Utils.scalars("aé€😀") == ["a", "é", "€", "😀"]

## Printable text is quoted as it reads, with quotes and backslashes escaped.
expect Utils.quote("--na\"me\\é") == "\"--na\\\"me\\\\é\""

## Control characters are never emitted raw by quoting.
expect Utils.quote("-\u(001b)[2J\n\u(0007)\u(009b)\u(202e)") == "\"-\\u(1b)[2J\\n\\u(7)\\u(9b)\\u(202e)\""

## Escaping controls without quoting leaves other text unchanged.
expect Utils.escape_controls("bad \"x\"\u(001b)") == "bad \"x\"\\u(1b)"

is_digit : U8 -> Bool
is_digit = |char| {
	zero_ascii_code = 48
	nine_ascii_code = 57

	char >= zero_ascii_code and char <= nine_ascii_code
}

is_lower_case : U8 -> Bool
is_lower_case = |char|
	char >= 'a' and char <= 'z'

## ASCII digits are recognized without accepting letters or spaces.
expect {
	sample = "19aB "

	sample.to_utf8().map(is_digit) == [True, True, False, False, False]
}

## Lowercase ASCII letters exclude uppercase letters and punctuation.
expect {
	sample = "aAzZ-"

	sample.to_utf8().map(is_lower_case) == [True, False, True, False, False]
}

## Kebab-case words may contain a separating dash.
expect Utils.is_kebab_case("abc-def")

## Kebab-case words cannot begin with a dash.
expect !(Utils.is_kebab_case("-abc-def"))

## Kebab-case words cannot end with a dash.
expect !(Utils.is_kebab_case("abc-def-"))

## A dash alone is not a kebab-case word.
expect !(Utils.is_kebab_case("-"))

## An empty string is not a kebab-case word.
expect !(Utils.is_kebab_case(""))

## Lowercase ASCII text is converted to uppercase.
expect Utils.to_upper_case("abc") == "ABC"

## Uppercase ASCII text remains unchanged.
expect Utils.to_upper_case("ABC") == "ABC"

## Case conversion preserves digits and punctuation.
expect Utils.to_upper_case("aBc00-") == "ABC00-"

## Quoting agrees with `Str.inspect` for printable text.
expect {
	sample = "it's a $test {x} ~`!@#%^&*()-_=+[]|;:,.<>/? é"

	Utils.quote(sample) == Str.inspect(sample)
}
