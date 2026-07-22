import ansi.ANSI
import ansi.C16 as AnsiC16
import ansi.Color as AnsiColor
import ansi.Style
import Base exposing [TextStyle]

Terminal := [].{

	## A piece of text carrying a semantic terminal style.
	Segment : {
		text : Str,
		style : [Accent, ErrorText, Frame, Heading, Hint, Label, Literal, Muted, PlainText, Section, Strong],
	}

	## Configuration for conservative word-boundary wrapping.
	WrapConfig : {
		first_indent : Str,
		continuation_indent : Str,
		width : U64,
	}

	plain : Str -> Terminal.Segment
	plain = |text| { text, style: PlainText }

	strong : Str -> Terminal.Segment
	strong = |text| { text, style: Strong }

	heading : Str -> Terminal.Segment
	heading = |text| { text, style: Heading }

	section : Str -> Terminal.Segment
	section = |text| { text, style: Section }

	accent : Str -> Terminal.Segment
	accent = |text| { text, style: Accent }

	label : Str -> Terminal.Segment
	label = |text| { text, style: Label }

	error : Str -> Terminal.Segment
	error = |text| { text, style: ErrorText }

	literal : Str -> Terminal.Segment
	literal = |text| { text, style: Literal }

	hint : Str -> Terminal.Segment
	hint = |text| { text, style: Hint }

	muted : Str -> Terminal.Segment
	muted = |text| { text, style: Muted }

	frame : Str -> Terminal.Segment
	frame = |text| { text, style: Frame }

	## Render semantic text, adding ANSI sequences only when color is requested.
	render : List(Terminal.Segment), TextStyle -> Str
	render = |segments, text_style|
		Str.join_with(segments.map(|segment| render_segment(segment, text_style)), "")

	## Wrap prose at whitespace boundaries without splitting UTF-8 tokens.
	## Byte length is deliberately conservative for non-ASCII terminal text.
	wrap : Str, Terminal.WrapConfig -> Str
	wrap = |text, config| {
		wrapped_state = 
			text.split_on("\n").fold(
				{ first: True, lines: [] },
				|acc, line| {
					first_indent = if acc.first {
						config.first_indent
					} else {
						config.continuation_indent
					}
					wrapped = wrap_logical_line(line, first_indent, config.continuation_indent, config.width)

					{ first: False, lines: acc.lines.concat(wrapped) }
				},
			)

		Str.join_with(wrapped_state.lines, "\n")
	}
}

render_segment : Terminal.Segment, TextStyle -> Str
render_segment = |{ text, style }, text_style| {
	styles : List(Style)
	styles = 
		match style {
			PlainText => []
			Strong => [Bold(On)]
			Heading | Label => [Bold(On), Foreground(AnsiColor.Standard(AnsiC16.Name.Cyan))]
			Section => [Bold(On), Underline(On), Foreground(AnsiColor.Standard(AnsiC16.Name.Cyan))]
			Accent => [Foreground(AnsiColor.Standard(AnsiC16.Name.Cyan))]
			ErrorText => [Bold(On), Foreground(AnsiColor.Standard(AnsiC16.Name.Red))]
			Literal => [Foreground(AnsiColor.Standard(AnsiC16.Name.Yellow))]
			Hint => [Bold(On), Foreground(AnsiColor.Standard(AnsiC16.Name.Green))]
			Muted | Frame => [Foreground(AnsiColor.Bright(AnsiC16.Name.Black))]
		}

	match text_style {
		Plain => text
		Color if styles.is_empty() => text
		Color => ANSI.style(text, styles).concat(ANSI.style("", [Default]))
	}
}

wrap_logical_line : Str, Str, Str, U64 -> List(Str)
wrap_logical_line = |line, first_indent, continuation_indent, width| {
	initial = {
		current: first_indent,
		has_word: False,
		lines: [],
		width: first_indent.count_utf8_bytes(),
	}
	line_state = 
		line
			.split_on(" ")
			.keep_if(|word| !word.is_empty())
			.fold(
				initial,
				|acc, word| {
					separator_width = if acc.has_word {
						1
					} else {
						0
					}
					word_width = word.count_utf8_bytes()
					would_overflow = acc.has_word and acc.width + separator_width + word_width > width

					if would_overflow {
						{
							current: "${continuation_indent}${word}",
							has_word: True,
							lines: acc.lines.append(acc.current),
							width: continuation_indent.count_utf8_bytes() + word_width,
						}
					} else {
						separator = if acc.has_word {
							" "
						} else {
							""
						}
						{
							current: "${acc.current}${separator}${word}",
							has_word: True,
							lines: acc.lines,
							width: acc.width + separator_width + word_width,
						}
					}
				},
			)

	line_state.lines.append(line_state.current)
}

## Wrapping preserves explicit lines and uses hanging indentation.
expect {
	actual = Terminal.wrap(
		"one two three\nfour",
		{ first_indent: "  ", continuation_indent: "    ", width: 11 },
	)

	actual == "  one two\n    three\n    four"
}

## Wrapping never splits a Unicode token, even when its byte length exceeds the limit.
expect {
	unicode_token = "👨‍👩‍👧‍👦é世界"
	actual = Terminal.wrap(
		"before ${unicode_token} after",
		{ first_indent: "", continuation_indent: "  ", width: 10 },
	)

	actual == "before\n  ${unicode_token}\n  after"
}

## ANSI styling is applied separately from layout.
expect {
	wrapped = Terminal.wrap("one two three", { first_indent: "", continuation_indent: "  ", width: 7 })
	colored = Terminal.render([Terminal.error(wrapped)], Color)

	wrapped == "one two\n  three"
		and colored == "\u(001b)[1m\u(001b)[31mone two\n  three\u(001b)[0m"
}
