## Pure byte and source-text helpers shared by the repository scripts.
Text := [].{

	## Normalise captured terminal output for comparison: CRLF and lone CR become
	## LF, and ANSI SGR sequences (`ESC [ ... m`) are removed.
	normalize : List(U8) -> List(U8)
	normalize = |bytes| strip_sgr(normalize_newlines(bytes, []), [])

	## Decode a string of hexadecimal byte pairs such as `"ff00"`.
	from_hex : Str -> Try(List(U8), [InvalidHex(Str)])
	from_hex = |value| decode_hex(Str.to_utf8(value), []).map_err(|_| InvalidHex(value))

	## Replace the one `name: "..."` package dependency line in a Roc app header,
	## keeping its indentation. Everything else in the source is left untouched.
	rewrite_dependency : Str, Str, Str -> Try(Str, [ExpectedOneDependency(Str, U64)])
	rewrite_dependency = |source, name, url| {
		lines = Str.split_on(source, "\n")
		count = lines.count_if(|line| is_dependency(line, name))
		if count == 1 {
			Ok(
				Str.join_with(
					lines.map(
						|line|
							if is_dependency(line, name) {
								"${indentation(line)}${name}: \"${url}\","
							} else {
								line
							},
					),
					"\n",
				),
			)
		} else {
			Err(ExpectedOneDependency(name, count))
		}
	}

	## The quoted value of each `name: "..."` dependency line in a Roc source file.
	dependency_values : Str, Str -> List(Str)
	dependency_values = |source, name|
		Str.split_on(source, "\n")
			.keep_if(|line| is_dependency(line, name))
			.map(
				|line|
					match Str.split_on(line, "\"") {
						[_, value, ..] => value
						_ => ""
					},
			)
}

normalize_newlines = |bytes, out|
	match bytes {
		[] => out
		['\r', '\n', .. as rest] => normalize_newlines(rest, out.append('\n'))
		['\r', .. as rest] => normalize_newlines(rest, out.append('\n'))
		[byte, .. as rest] => normalize_newlines(rest, out.append(byte))
	}

strip_sgr = |bytes, out|
	match bytes {
		[] => out
		[27, '[', .. as rest] =>
			match sgr_end(rest) {
				Ok(after) => strip_sgr(after, out)
				Err(NotSgr) => strip_sgr(rest, out.append(27).append('['))
			}
		[byte, .. as rest] => strip_sgr(rest, out.append(byte))
	}

sgr_end = |bytes|
	match bytes {
		['m', .. as rest] => Ok(rest)
		[byte, .. as rest] if (byte >= '0' and byte <= '9') or byte == ';' => sgr_end(rest)
		_ => Err(NotSgr)
	}

decode_hex = |bytes, out|
	match bytes {
		[] => Ok(out)
		[high, low, .. as rest] => decode_hex(rest, out.append(hex_digit(high)? * 16 + hex_digit(low)?))
		[_] => Err(OddLength)
	}

hex_digit = |byte|
	if byte >= '0' and byte <= '9' {
		Ok(byte - '0')
	} else if byte >= 'a' and byte <= 'f' {
		Ok(byte - 'a' + 10)
	} else if byte >= 'A' and byte <= 'F' {
		Ok(byte - 'A' + 10)
	} else {
		Err(NotHex)
	}

is_dependency = |line, name| Str.trim_start(line).starts_with("${name}: \"")

indentation = |line| {
	trimmed = Str.trim_start(line)
	Str.from_utf8_lossy(Str.to_utf8(line).take_first(Str.to_utf8(line).len() - Str.to_utf8(trimmed).len()))
}

expect Text.normalize(Str.to_utf8("a\r\nb\rc\n")) == Str.to_utf8("a\nb\nc\n")
expect Text.normalize([27, '[', '1', ';', '3', '6', 'm', 'h', 'i', 27, '[', '0', 'm']) == ['h', 'i']
expect Text.normalize([27, '[', '2', 'K', 'x']) == [27, '[', '2', 'K', 'x']
expect Text.from_hex("ff00Ab") == Ok([255, 0, 171])
expect Text.from_hex("f") == Err(InvalidHex("f"))
expect Text.from_hex("zz") == Err(InvalidHex("zz"))
expect Text.rewrite_dependency("app [main!] {\n\tpf: platform \"p\",\n\tweaver: \"../package/main.roc\",\n}\n", "weaver", "http://x/y.tar.zst") == Ok("app [main!] {\n\tpf: platform \"p\",\n\tweaver: \"http://x/y.tar.zst\",\n}\n")
expect Text.rewrite_dependency("app [main!] {}\n", "weaver", "u") == Err(ExpectedOneDependency("weaver", 0))
expect Text.dependency_values("\tweaver: \"../package/main.roc\",\n", "weaver") == ["../package/main.roc"]
expect Text.dependency_values("\troc: \"nightly-1\",\n", "weaver") == []
