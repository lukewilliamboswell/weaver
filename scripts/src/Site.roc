## Pure HTML generation for the documentation site.
Site := [].{

	## Escape text for an HTML element or attribute value.
	escape : Str -> Str
	escape = |text|
		text
			.replace_each("&", "&amp;")
			.replace_each("<", "&lt;")
			.replace_each(">", "&gt;")
			.replace_each("\"", "&quot;")
			.replace_each("'", "&#x27;")

	## Join a command line the way a POSIX shell would need it typed.
	shell_join : List(Str) -> Str
	shell_join = |words| Str.join_with(words.map(shell_quote), " ")

	## The landing-page card showing one example's command and terminal output.
	example_card : Str, Str, Str -> Str
	example_card = |name, command, output| {
		body = "<span class=\"prompt\">$</span> ${escape(command)}\n${escape(Str.trim_end(output))}"
		Str.join_with(
			[
				"<a class=\"example\" href=\"https://github.com/lukewilliamboswell/weaver/blob/main/examples/${name}.roc\">",
				"<span class=\"example-name\">${escape(example_title(name))}<span class=\"example-file\">${name}.roc</span></span>",
				"<span class=\"terminal-window\">",
				"<span class=\"terminal-title\" aria-hidden=\"true\"><i></i><i></i><i></i></span>",
				"<pre><code>${body}</code></pre>",
				"</span></a>",
			],
			"",
		)
	}

	## Put the example cards where the landing page marks their place.
	insert_examples : Str, List(Str) -> Try(Str, [MissingExamplesPlaceholder])
	insert_examples = |document, cards|
		if document.contains(examples_placeholder) {
			Ok(document.replace_first(examples_placeholder, "<div class=\"example-grid\">${Str.join_with(cards, "")}</div>"))
		} else {
			Err(MissingExamplesPlaceholder)
		}

	## Brand one generated API page and add the syntax highlighter. `depth` is
	## how many directories the page sits below the site root, so the package
	## landing page `main/index.html` has depth 1. Already enhanced pages are
	## returned as `Unchanged`.
	enhance_api_page : Str, U64 -> Try([Changed(Str), Unchanged], [IncompleteDocument, NoPackageHeading, NoIndexDecoration])
	enhance_api_page = |document, depth| {
		if assets.all(|asset| document.contains(asset)) {
			return Ok(Unchanged)
		}
		if !document.contains("</head>") or !document.contains("</body>") {
			return Err(IncompleteDocument)
		}
		home = Str.repeat("../", depth)
		branded = rebrand(document, home, depth == 1)?
		styles = Str.join_with(
			["roc-highlight.css", "docs-extras.css"].map(|asset| "    <link rel=\"stylesheet\" href=\"${home}${asset}\">\n"),
			"",
		)
		Ok(
			Changed(
				branded
					.replace_first("</head>", "${styles}</head>")
					.replace_first("</body>", "    <script type=\"module\" src=\"${home}roc-highlight.js\"></script>\n</body>"),
			),
		)
	}
}

assets = ["roc-highlight.js", "roc-highlight.css", "docs-extras.css"]

examples_placeholder = "<!--EXAMPLES-->"

example_title = |name|
	match name {
		"basic" => "Basic"
		"default-values" => "Default values"
		"deploy" => "Deploy"
		"single-arg" => "Single argument"
		"subcommands" => "Subcommands"
		_ => name
	}

shell_quote = |word|
	if word != "" and Str.to_utf8(word).all(shell_safe) {
		word
	} else {
		"'${word.replace_each("'", "'\"'\"'")}'"
	}

shell_safe = |byte|
	(byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or (byte >= '0' and byte <= '9') or "@%+=:,./-_".to_utf8().contains(byte)

# Roc names the package after its directory, "package", and leaves the package
# landing page empty. Use the real name, link back to the site, and give the
# landing page an entry point.
rebrand = |document, home, is_landing| {
	titled = document.replace_first("<title>package Docs</title>", "<title>Weaver Docs</title>")
	marker = "<h1 class=\"pkg-full-name\">"
	heading = titled.split_first(marker).map_err(|_| NoPackageHeading)?
	rest = heading.after.split_first("</h1>").map_err(|_| NoPackageHeading)?
	linked = Str.join_with(
		[
			heading.before,
			"${marker}<a href=\"${home}\">Weaver</a></h1>",
			"<p class=\"pkg-site-link\"><a href=\"${home}\">\u(2190) Back to the Weaver site</a></p>",
			rest.after,
		],
		"",
	)
	if is_landing {
		decoration = "<div class=\"index-decoration\">"
		if linked.contains(decoration) {
			Ok(linked.replace_first(decoration, "${intro}${decoration}"))
		} else {
			Err(NoIndexDecoration)
		}
	} else {
		Ok(linked)
	}
}

intro =
	\\<section class="pkg-intro">
	\\    <h2>Weaver API documentation</h2>
	\\    <p>Weaver builds type-safe command-line interfaces in Roc. Compose options, parameters,
	\\    and nested subcommands with builders, then let Weaver handle parsing, validation,
	\\    diagnostics, help, and version output.</p>
	\\    <p>Pick a module from the sidebar, or search above. Start with
	\\    <a href="Cli/">Cli</a> for assembling and running a parser,
	\\    <a href="Opt/">Opt</a> and <a href="Param/">Param</a> for individual arguments, and
	\\    <a href="SubCmd/">SubCmd</a> for nested commands.</p>
	\\</section>
	\\

expect Site.escape("<a href=\"x\">it's & more</a>") == "&lt;a href=&quot;x&quot;&gt;it&#x27;s &amp; more&lt;/a&gt;"
expect Site.shell_join(["./basic", "-a", "1"]) == "./basic -a 1"
expect Site.shell_join(["./deploy", "team=a b", "it's", ""]) == "./deploy 'team=a b' 'it'\"'\"'s' ''"
expect Site.insert_examples("<p><!--EXAMPLES--></p>", ["A", "B"]) == Ok("<p><div class=\"example-grid\">AB</div></p>")
expect Site.insert_examples("<p></p>", []) == Err(MissingExamplesPlaceholder)
expect Site.enhance_api_page("<html></html>", 1) == Err(IncompleteDocument)
expect Site.enhance_api_page("<head></head><body></body>", 2) == Err(NoPackageHeading)
expect Site.enhance_api_page("<head></head><body><h1 class=\"pkg-full-name\">package</h1></body>", 2) == Ok(Changed("<head>    <link rel=\"stylesheet\" href=\"../../roc-highlight.css\">\n    <link rel=\"stylesheet\" href=\"../../docs-extras.css\">\n</head><body><h1 class=\"pkg-full-name\"><a href=\"../../\">Weaver</a></h1><p class=\"pkg-site-link\"><a href=\"../../\">\u(2190) Back to the Weaver site</a></p>    <script type=\"module\" src=\"../../roc-highlight.js\"></script>\n</body>"))
expect Site.enhance_api_page("roc-highlight.js roc-highlight.css docs-extras.css", 1) == Ok(Unchanged)
