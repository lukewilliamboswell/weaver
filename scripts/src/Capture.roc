## Pure rendering of a terminal session, with ANSI SGR styling, as an SVG.
Capture := [].{

	## The source between `# capture:start` and `# capture:end`, with line
	## numbers and syntax colours expressed as SGR sequences.
	source_excerpt : Str -> Try(Str, [MissingCaptureMarkers])
	source_excerpt = |source| {
		after = source.split_first("# capture:start").map_err(|_| MissingCaptureMarkers)?.after
		excerpt = after.split_first("# capture:end").map_err(|_| MissingCaptureMarkers)?.before
		lines = Str.split_on(trim_newlines(excerpt), "\n")
		Ok(
			Str.join_with(
				lines.map_with_index(
					|line, index| {
						number = (index + 1).to_str()
						padded = if index + 1 < 10 " ${number}" else number
						"\u(1b)[90m${padded} \u(2502)\u(1b)[0m ${highlight(line).replace_each("\t", "    ")}"
					},
				),
				"\n",
			),
		)
	}

	## A shell prompt line for `command`.
	prompt : Str -> Str
	prompt = |command| "\u(1b)[1;32m$\u(1b)[0m \u(1b)[1m${command}\u(1b)[0m"

	## Render terminal text as an SVG terminal window.
	svg : Str -> Str
	svg = |terminal_text| {
		lines = Str.split_on(terminal_text, "\n")
		longest = lines.map(|line| code_points(strip_sgr(Str.to_utf8(line), []))).fold(0, |a, b| if a > b a else b)
		width = max_u64(760, (longest * 845 + 4800) // 100)
		height = 38 + 40 + lines.len() * 22
		half_width = if width % 2 == 0 "${(width // 2).to_str()}.0" else "${(width // 2).to_str()}.5"
		rendered = render_lines(lines, 0, default_style, [])
		Str.join_with(
			[
				"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"${width.to_str()}\" height=\"${height.to_str()}\" viewBox=\"0 0 ${width.to_str()} ${height.to_str()}\" role=\"img\" aria-labelledby=\"title description\">",
				"  <title id=\"title\">Weaver deployment CLI showcase</title>",
				"  <desc id=\"description\">Roc record-builder source followed by a successful typed deployment plan and a structured missing-option diagnostic.</desc>",
				"  <rect width=\"${width.to_str()}\" height=\"${height.to_str()}\" rx=\"10\" fill=\"#0d1117\"/>",
				"  <path d=\"M10 0h${(width - 20).to_str()}a10 10 0 0 1 10 10v28H0V10A10 10 0 0 1 10 0z\" fill=\"#161b22\"/>",
				"  <circle cx=\"20\" cy=\"19\" r=\"5\" fill=\"#ff7b72\"/>",
				"  <circle cx=\"38\" cy=\"19\" r=\"5\" fill=\"#d29922\"/>",
				"  <circle cx=\"56\" cy=\"19\" r=\"5\" fill=\"#3fb950\"/>",
				"  <text x=\"${half_width}\" y=\"24\" text-anchor=\"middle\" fill=\"#8b949e\" font-family=\"ui-sans-serif, system-ui, sans-serif\" font-size=\"12\">Weaver \u(b7) deploy showcase</text>",
				"  <g font-family=\"ui-monospace, SFMono-Regular, Menlo, Consolas, 'Liberation Mono', monospace\" font-size=\"14\">",
				"    ${Str.join_with(rendered, "\n")}",
				"  </g>",
				"</svg>",
				"",
			],
			"\n",
		)
	}
}

Style : { foreground : Str, bold : Bool, underline : Bool }

default_style : Style
default_style = { foreground: "#c9d1d9", bold: Bool.False, underline: Bool.False }

max_u64 : U64, U64 -> U64
max_u64 = |a, b| if a > b a else b

trim_newlines = |text| {
	without_leading = if text.starts_with("\n") trim_newlines(Str.drop_prefix(text, "\n")) else text
	if without_leading.ends_with("\n") trim_newlines(Str.drop_suffix(without_leading, "\n")) else without_leading
}

# Colour string literals green, and comments and capitalised names cyan.
highlight = |line| Str.from_utf8_lossy(highlight_bytes(Str.to_utf8(line), Bool.False, []))

highlight_bytes = |bytes, after_word, out|
	match bytes {
		[] => out
		['"', .. as rest] =>
			match string_end(rest, ['"']) {
				Ok({ token, after }) => highlight_bytes(after, Bool.False, colored(out, 32, token))
				Err(Unterminated) => highlight_bytes(rest, Bool.False, out.append('"'))
			}
		['#', ..] => colored(out, 36, bytes)
		[byte, ..] if byte >= 'A' and byte <= 'Z' and !after_word => {
			run = name_run(bytes, [])
			token = drop_trailing_dots(run)
			highlight_bytes(bytes.drop_first(token.len()), Bool.True, colored(out, 36, token))
		}
		[byte, .. as rest] => highlight_bytes(rest, word_byte(byte), out.append(byte))
	}

string_end = |bytes, token|
	match bytes {
		['"', .. as after] => Ok({ token: token.append('"'), after })
		['\\', escaped, .. as rest] => string_end(rest, token.append('\\').append(escaped))
		[byte, .. as rest] if byte != '\\' => string_end(rest, token.append(byte))
		_ => Err(Unterminated)
	}

name_run = |bytes, run|
	match bytes {
		[byte, .. as rest] if word_byte(byte) or byte == '.' => name_run(rest, run.append(byte))
		_ => run
	}

drop_trailing_dots = |run|
	match run {
		[.. as init, '.'] => drop_trailing_dots(init)
		_ => run
	}

word_byte = |byte|
	(byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or (byte >= '0' and byte <= '9') or byte == '_'

colored : List(U8), U64, List(U8) -> List(U8)
colored = |out, color, token|
	out.concat(Str.to_utf8("\u(1b)[${color.to_str()}m")).concat(token).concat(Str.to_utf8("\u(1b)[0m"))

strip_sgr = |bytes, out|
	match bytes {
		[] => out
		[27, '[', .. as rest] =>
			match sgr(rest, []) {
				Ok(parsed) => strip_sgr(parsed.after, out)
				Err(NotSgr) => strip_sgr(rest, out.append(27).append('['))
			}
		[byte, .. as rest] => strip_sgr(rest, out.append(byte))
	}

# Parse the parameters of an SGR sequence after its `ESC [` introducer.
sgr = |bytes, params|
	match bytes {
		['m', .. as after] => Ok({ params, after })
		[byte, .. as rest] if (byte >= '0' and byte <= '9') or byte == ';' => sgr(rest, params.append(byte))
		_ => Err(NotSgr)
	}

code_points = |bytes| bytes.count_if(|byte| byte < 128 or byte >= 192)

render_lines : List(Str), U64, Style, List(Str) -> List(Str)
render_lines = |lines, index, style, rendered|
	match lines {
		[] => rendered
		[line, .. as rest] => {
			result = styled_runs(Str.to_utf8(line), style, [], [])
			spans = result.runs.map(
				|run| {
					bold = if run.style.bold " font-weight=\"700\"" else ""
					underline = if run.style.underline " text-decoration=\"underline\"" else ""
					"<tspan fill=\"${run.style.foreground}\"${bold}${underline}>${escape(Str.from_utf8_lossy(run.text))}</tspan>"
				},
			)
			y = 38 + 20 + 14 + index * 22
			text = "<text x=\"24\" y=\"${y.to_str()}\" xml:space=\"preserve\">${Str.join_with(spans, "")}</text>"
			render_lines(rest, index + 1, result.style, rendered.append(text))
		}
	}

styled_runs = |bytes, style, pending, runs|
	match bytes {
		[] => { runs: flush(runs, pending, style), style }
		[27, '[', .. as rest] =>
			match sgr(rest, []) {
				Ok({ params, after }) => styled_runs(after, apply_sgr(style, codes(params)), [], flush(runs, pending, style))
				Err(NotSgr) => styled_runs(rest, style, pending.append(27).append('['), runs)
			}
		[byte, .. as rest] => styled_runs(rest, style, pending.append(byte), runs)
	}

flush = |runs, pending, style| if pending.is_empty() runs else runs.append({ text: pending, style })

codes = |params| {
	parsed = Str.split_on(Str.from_utf8_lossy(params), ";").keep_if(|code| code != "").map(|code| U64.from_str(code) ?? 0)
	if parsed.is_empty() [0] else parsed
}

apply_sgr : Style, List(U64) -> Style
apply_sgr = |style, sgr_codes|
	sgr_codes.fold(
		style,
		|current, code|
			match code {
				0 => default_style
				1 => { ..current, bold: Bool.True }
				4 => { ..current, underline: Bool.True }
				22 => { ..current, bold: Bool.False }
				24 => { ..current, underline: Bool.False }
				39 => { ..current, foreground: default_style.foreground }
				_ =>
					match color(code) {
						Ok(foreground) => { ..current, foreground }
						Err(NoColor) => current
					}
			},
	)

color = |code|
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
		_ => Err(NoColor)
	}

escape = |text|
	text
		.replace_each("&", "&amp;")
		.replace_each("<", "&lt;")
		.replace_each(">", "&gt;")
		.replace_each("\"", "&quot;")
		.replace_each("'", "&#x27;")

expect highlight("x = Opt.str(\"a b\") # Note") == "x = \u(1b)[36mOpt.str\u(1b)[0m(\u(1b)[32m\"a b\"\u(1b)[0m) \u(1b)[36m# Note\u(1b)[0m"
expect highlight("aB Cli. ok") == "aB \u(1b)[36mCli\u(1b)[0m. ok"
expect Capture.source_excerpt("a\n# capture:start\nx\n\ty\n# capture:end\nb") == Ok("\u(1b)[90m 1 \u(2502)\u(1b)[0m x\n\u(1b)[90m 2 \u(2502)\u(1b)[0m     y")
expect Capture.source_excerpt("no markers") == Err(MissingCaptureMarkers)
expect code_points(Str.to_utf8("a\u(2502)b")) == 3
expect styled_runs(Str.to_utf8("\u(1b)[1;31mred\u(1b)[0m plain"), default_style, [], []).runs == [{ text: Str.to_utf8("red"), style: { foreground: "#ff7b72", bold: Bool.True, underline: Bool.False } }, { text: Str.to_utf8(" plain"), style: default_style }]
