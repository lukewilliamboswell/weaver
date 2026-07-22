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
}

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
