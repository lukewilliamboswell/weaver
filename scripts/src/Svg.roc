## Pure rendering of terminal text as the README's SVG screenshot.
##
## The text carries SGR escape sequences, as the deploy example prints them.
## Each line becomes one `<text>` element whose runs keep their colour, weight
## and underline.
Svg := [].{

	## Colour Roc source the way the screenshot shows it: strings green, and
	## comments and capitalised names cyan. Lines are numbered, and tabs are
	## expanded to four columns.
	highlight : Str -> Str
	highlight = |source| {
		var $lines = []
		var $number = 0.U64
		for line in Str.split_on(source, "\n") {
			$number = $number + 1
			code = expand_tabs(highlight_line(Str.to_utf8(line), []))
			gutter = if ($number < 10) " ${$number.to_str()}" else $number.to_str()
			$lines = $lines.append("\u(1b)[90m${gutter} │\u(1b)[0m ${code}")
		}
		Str.join_with($lines, "\n")
	}

	## The text between the `# capture:start` and `# capture:end` lines of
	## `source`, without the newlines around it.
	excerpt : Str -> Try(Str, [MissingMarkers])
	excerpt = |source|
		match Str.split_first(source, "# capture:start") {
			Ok({ after, .. }) =>
				match Str.split_first(after, "# capture:end") {
					Ok({ before, .. }) => Ok(trim_newlines(before))
					Err(_) => Err(MissingMarkers)
				}
			Err(_) => Err(MissingMarkers)
		}

	## A shell prompt for `command`, as the screenshot shows it.
	prompt : Str -> Str
	prompt = |command| "\u(1b)[1;32m$\u(1b)[0m \u(1b)[1m${command}\u(1b)[0m"

	## The whole SVG document for `terminal_text`.
	render : Str -> Str
	render = |terminal_text| {
		lines = Str.split_on(terminal_text, "\n")
		longest = lines.map(|line| code_points(strip_sgr(line))).max() ?? 0
		# 8.45 pixels a character and 24 pixels each side, at least 760 wide.
		width = (longest * 845 // 100 + 48).max(760)
		height = 38 + 40 + lines.len() * 22
		var $rendered = []
		var $style = plain
		var $index = 0.U64
		for line in lines {
			{ runs, style } = styled_runs(line, $style)
			$style = style
			spans = runs.map(|(text, run_style)| "<tspan ${attributes(run_style)}>${escape(text)}</tspan>")
			y = 38 + 20 + 14 + $index * 22
			$rendered = $rendered.append("<text x=\"24\" y=\"${y.to_str()}\" xml:space=\"preserve\">${Str.join_with(spans, "")}</text>")
			$index = $index + 1
		}
		middle = if (width % 2 == 0) "${(width // 2).to_str()}.0" else "${(width // 2).to_str()}.5"
		w = width.to_str()
		h = height.to_str()
		Str.join_with(
			[
				"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"${w}\" height=\"${h}\" viewBox=\"0 0 ${w} ${h}\" role=\"img\" aria-labelledby=\"title description\">",
				"  <title id=\"title\">Weaver deployment CLI showcase</title>",
				"  <desc id=\"description\">Roc record-builder source followed by a successful typed deployment plan and a structured missing-option diagnostic.</desc>",
				"  <rect width=\"${w}\" height=\"${h}\" rx=\"10\" fill=\"#0d1117\"/>",
				"  <path d=\"M10 0h${(width - 20).to_str()}a10 10 0 0 1 10 10v28H0V10A10 10 0 0 1 10 0z\" fill=\"#161b22\"/>",
				"  <circle cx=\"20\" cy=\"19\" r=\"5\" fill=\"#ff7b72\"/>",
				"  <circle cx=\"38\" cy=\"19\" r=\"5\" fill=\"#d29922\"/>",
				"  <circle cx=\"56\" cy=\"19\" r=\"5\" fill=\"#3fb950\"/>",
				"  <text x=\"${middle}\" y=\"24\" text-anchor=\"middle\" fill=\"#8b949e\" font-family=\"ui-sans-serif, system-ui, sans-serif\" font-size=\"12\">Weaver · deploy showcase</text>",
				"  <g font-family=\"ui-monospace, SFMono-Regular, Menlo, Consolas, 'Liberation Mono', monospace\" font-size=\"14\">",
				"    ${Str.join_with($rendered, "\n")}",
				"  </g>",
				"</svg>",
				"",
			],
			"\n",
		)
	}
}

Style : { foreground : Str, bold : Bool, underline : Bool }

plain : Style
plain = { foreground: "#c9d1d9", bold: False, underline: False }

# Tokens are found left to right: a string literal, then a comment, then a
# name starting with a capital letter at a word boundary.
highlight_line : List(U8), List(U8) -> Str
highlight_line = |bytes, previous|
	match bytes {
		[] => ""
		['"', .. as rest] =>
			match string_length(rest, 0) {
				Ok(length) => coloured(32, bytes.take_first(length + 1), bytes.drop_first(length + 1))
				Err(Unterminated) => plain_byte(bytes)
			}
		['#', ..] => coloured(36, bytes, [])
		[first, ..] if is_upper(first) and !ends_in_word(previous) => {
			taken = bytes.take_first(name_length(bytes, 0))
			# The name must end at a word boundary, so trailing dots stay out.
			name = drop_trailing_dots(taken)
			coloured(36, name, bytes.drop_first(name.len()))
		}
		[_, ..] => plain_byte(bytes)
	}

plain_byte : List(U8) -> Str
plain_byte = |bytes| {
	byte = bytes.take_first(1)
	"${Str.from_utf8_lossy(byte)}${highlight_line(bytes.drop_first(1), byte)}"
}

coloured : U64, List(U8), List(U8) -> Str
coloured = |colour, token, rest|
	"\u(1b)[${colour.to_str()}m${Str.from_utf8_lossy(token)}\u(1b)[0m${highlight_line(rest, token)}"

# The length of a string literal's body and closing quote, after its opening quote.
string_length : List(U8), U64 -> Try(U64, [Unterminated])
string_length = |bytes, length|
	match bytes {
		['"', ..] => Ok(length + 1)
		['\\', _, .. as rest] => string_length(rest, length + 2)
		['\n', ..] | ['\\'] | [] => Err(Unterminated)
		[_, .. as rest] => string_length(rest, length + 1)
	}

name_length : List(U8), U64 -> U64
name_length = |bytes, length|
	match bytes {
		[byte, .. as rest] if is_word(byte) or byte == '.' => name_length(rest, length + 1)
		_ => length
	}

drop_trailing_dots : List(U8) -> List(U8)
drop_trailing_dots = |bytes|
	match bytes.last() {
		Ok('.') => drop_trailing_dots(bytes.drop_last(1))
		_ => bytes
	}

ends_in_word : List(U8) -> Bool
ends_in_word = |bytes|
	match bytes.last() {
		Ok(byte) => is_word(byte)
		Err(_) => False
	}

is_upper : U8 -> Bool
is_upper = |byte| byte >= 'A' and byte <= 'Z'

is_word : U8 -> Bool
is_word = |byte| (byte >= 'a' and byte <= 'z') or is_upper(byte) or (byte >= '0' and byte <= '9') or byte == '_'

# Expand each tab to the next multiple of four columns, counting every code
# point, escape sequences included, as one column.
expand_tabs : Str -> Str
expand_tabs = |text| {
	var $out = []
	var $column = 0
	for byte in Str.to_utf8(text) {
		if byte == '\t' {
			spaces = 4 - $column % 4
			$out = $out.concat(List.repeat(' ', spaces))
			$column = $column + spaces
		} else {
			$out = $out.append(byte)
			if byte.bitwise_and(0xC0) != 0x80 {
				$column = $column + 1
			}
		}
	}
	Str.from_utf8_lossy($out)
}

code_points : Str -> U64
code_points = |text| Str.to_utf8(text).count_if(|byte| byte.bitwise_and(0xC0) != 0x80)

trim_newlines : Str -> Str
trim_newlines = |text| {
	bytes = Str.to_utf8(text)
	trimmed = bytes.drop_first(count_while(bytes, |byte| byte == '\n'))
	end = count_while(trimmed.rev(), |byte| byte == '\n')
	Str.from_utf8_lossy(trimmed.drop_last(end))
}

count_while : List(U8), (U8 -> Bool) -> U64
count_while = |bytes, predicate|
	match bytes {
		[byte, .. as rest] if predicate(byte) => 1 + count_while(rest, predicate)
		_ => 0
	}

strip_sgr : Str -> Str
strip_sgr = |line| Str.join_with(styled_runs(line, plain).runs.map(|(text, _)| text), "")

# Split `line` into runs of one style, starting from `initial`, and return the
# style in force at its end, which the next line starts with.
styled_runs : Str, Style -> { runs : List((Str, Style)), style : Style }
styled_runs = |line, initial| scan(Str.to_utf8(line), [], initial, [])

scan : List(U8), List(U8), Style, List((Str, Style)) -> { runs : List((Str, Style)), style : Style }
scan = |bytes, text, style, runs|
	match bytes {
		[] => { runs: flush(runs, text, style), style }
		[27, '[', .. as rest] =>
			match sgr_codes(rest, []) {
				Ok({ codes, after }) => scan(after, [], apply(codes, style), flush(runs, text, style))
				Err(NotSgr) => scan(bytes.drop_first(1), text.append(27), style, runs)
			}
		[byte, .. as rest] => scan(rest, text.append(byte), style, runs)
	}

flush = |runs, text, style| if (text.is_empty()) runs else runs.append((Str.from_utf8_lossy(text), style))

# The codes of a sequence of digits and semicolons ended by `m`, and what follows it.
sgr_codes : List(U8), List(U8) -> Try({ codes : List(U64), after : List(U8) }, [NotSgr])
sgr_codes = |bytes, digits|
	match bytes {
		['m', .. as after] => {
			codes = Str.split_on(Str.from_utf8_lossy(digits), ";").keep_if(|code| code != "").map(|code| U64.from_str(code).ok_or(0))
			Ok({ codes, after })
		}
		[byte, .. as rest] if byte == ';' or (byte >= '0' and byte <= '9') => sgr_codes(rest, digits.append(byte))
		_ => Err(NotSgr)
	}

apply : List(U64), Style -> Style
apply = |codes, style|
	(if (codes.is_empty()) [0] else codes).fold(
		style,
		|current, code|
			match code {
				0 => plain
				1 => { ..current, bold: True }
				4 => { ..current, underline: True }
				22 => { ..current, bold: False }
				24 => { ..current, underline: False }
				39 => { ..current, foreground: plain.foreground }
				_ =>
					match colour(code) {
						Ok(value) => { ..current, foreground: value }
						Err(_) => current
					}
			},
	)

colour : U64 -> Try(Str, [Unknown])
colour = |code|
	match code {
		30 => Ok("#484f58")
		31 => Ok("#ff7b72")
		32 => Ok("#3fb950")
		33 => Ok("#d29922")
		34 => Ok("#58a6ff")
		35 => Ok("#bc8cff")
		36 => Ok("#39c5cf")
		37 => Ok("#c9d1d9")
		90 => Ok("#8b949e")
		91 => Ok("#ff7b72")
		92 => Ok("#56d364")
		93 => Ok("#e3b341")
		94 => Ok("#79c0ff")
		95 => Ok("#d2a8ff")
		96 => Ok("#56d4dd")
		97 => Ok("#f0f6fc")
		_ => Err(Unknown)
	}

attributes : Style -> Str
attributes = |style|
	Str.join_with(
		["fill=\"${style.foreground}\""]
			.concat(if (style.bold) ["font-weight=\"700\""] else [])
			.concat(if (style.underline) ["text-decoration=\"underline\""] else []),
		" ",
	)

escape : Str -> Str
escape = |text|
	text
		.replace_each("&", "&amp;")
		.replace_each("<", "&lt;")
		.replace_each(">", "&gt;")
		.replace_each("\"", "&quot;")
		.replace_each("'", "&#x27;")

expect Svg.excerpt("a\n# capture:start\n\nx\ny\n\n# capture:end\nb") == Ok("x\ny")
expect Svg.excerpt("no markers") == Err(MissingMarkers)
expect Svg.highlight("\tfoo : \"a\\\"b\" # Note") == "\u(1b)[90m 1 │\u(1b)[0m     foo : \u(1b)[32m\"a\\\"b\"\u(1b)[0m \u(1b)[36m# Note\u(1b)[0m"
expect Svg.highlight("x = Opt.u64(Cli.) aB") == "\u(1b)[90m 1 │\u(1b)[0m x = \u(1b)[36mOpt.u64\u(1b)[0m(\u(1b)[36mCli\u(1b)[0m.) aB"
expect Svg.highlight("\"open") == "\u(1b)[90m 1 │\u(1b)[0m \"open"
expect styled_runs("a\u(1b)[1;31mb\u(1b)[0mc", plain).runs == [("a", plain), ("b", { foreground: "#ff7b72", bold: True, underline: False }), ("c", plain)]
expect styled_runs("\u(1b)[4mx", plain).style.underline
expect escape("<a href='x'>&\"") == "&lt;a href=&#x27;x&#x27;&gt;&amp;&quot;"
expect expand_tabs("ab\tc") == "ab  c" and expand_tabs("│\t") == "│   "
