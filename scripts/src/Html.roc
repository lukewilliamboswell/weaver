import Text

## Pure rewriting of the API reference pages on the documentation site.
##
## `roc docs` knows nothing about the site around it. These functions name its
## pages after the package and link them back to the manual.
Html := [].{

	## Where GitHub Pages serves the site from.
	base_path : Str
	base_path = "/weaver"

	## Map the path of a preview request to what answers it: a file inside the
	## site, given as path segments, or a redirect. A path that could leave the
	## site, or names a hidden file, is not found.
	route : Str -> [File(List(Str)), Redirect(Str), NotFound]
	route = |path|
		if path == "/" or path == Html.base_path {
			Redirect("${Html.base_path}/")
		} else if !path.starts_with("${Html.base_path}/") {
			NotFound
		} else {
			relative = path.drop_prefix("${Html.base_path}/")
			segments = Str.split_on(if (relative == "" or relative.ends_with("/")) "${relative}index.html" else relative, "/")
			if segments.all(|segment| segment != "" and !segment.starts_with(".") and !segment.contains("\\")) {
				File(segments)
			} else {
				NotFound
			}
		}

	## The relative link from `page` to the site root, ending in a slash.
	## `page` is relative to the site root, such as `main/ANSI/index.html`.
	root_of : Str -> Str
	root_of = |page|
		match Str.split_on(page, "/").len() - 1 {
			0 => "./"
			depth => Str.repeat("../", depth)
		}

	## Rewrite one page of API reference. A page `roc docs` did not generate
	## is returned as it is.
	enhance : Str, Str -> Try(Str, [IncompletePage])
	enhance = |document, page| {
		if !document.contains("</head>") or !document.contains("</body>") {
			return Err(IncompletePage)
		}
		root = Html.root_of(page)
		if document.contains("id=\"sidebar-nav\"") {
			Ok(add_intro(replace_footer(add_site_link(rename_package(retitle(add_stylesheet(document, "docs-site.css", root))), root), root), root))
		} else {
			Ok(document)
		}
	}
}

package_name = "weaver"

add_stylesheet = |document, asset, prefix|
	if document.contains(asset) {
		document
	} else {
		Str.replace_first(document, "</head>", "    <link rel=\"stylesheet\" href=\"${prefix}${asset}\">\n</head>")
	}

# `roc docs` names the package after its directory, which is `package`.
retitle = |document|
	if document.contains("<title>package Docs</title>") {
		Str.replace_first(document, "<title>package Docs</title>", "<title>${package_name} API documentation</title>")
	} else {
		match Str.split_first(document, "<title>") {
			Ok({ before, after }) =>
				match Str.split_first(after, " Docs</title>") {
					Ok({ before: module_name, after: rest }) if Text.is_plain(module_name, "_") => "${before}<title>${module_name} · ${package_name}</title>${rest}"
					_ => document
				}
			Err(_) => document
		}
	}

rename_package = |document| {
	opening = "<h1 class=\"pkg-full-name\"><a href=\""
	closing = "\">package</a></h1>"
	match Str.split_first(document, opening) {
		Ok({ before, after }) =>
			match Str.split_first(after, "\"") {
				Ok({ before: href, after: _ }) if after.drop_prefix(href).starts_with(closing) => {
					link = if (href == "") "." else href
					"${before}${opening}${link}\">${package_name}</a></h1>${after.drop_prefix(href).drop_prefix(closing)}"
				}
				_ => document
			}
		Err(_) => document
	}
}

# The sidebar grid expects exactly two rows, so the link back to the site goes
# inside the module list.
add_site_link = |document, root|
	Str.replace_first(
		document,
		"<ul class=\"module-links\">",
		"<ul class=\"module-links\">\n                <li class=\"sidebar-entry sidebar-site-link\"><a href=\"${root}\">← ${package_name} manual</a></li>",
	)

replace_footer = |document, root|
	Str.replace_first(
		document,
		"<footer><p>Made by people who like to make nice things.</p></footer>",
		"<footer><p><a href=\"${root}\">${package_name}</a> is open source under the UPL-1.0 license.</p></footer>",
	)

# The package has no doc comment, so the index of the generated docs is
# otherwise empty. `roc docs` opens the content with a short `<!--!…-->` marker.
add_intro = |document, root| {
	opening = "<div class=\"main-content\">"
	if !document.contains("class=\"docs-index\"") {
		return document
	}
	match Str.split_first(document, opening) {
		Ok({ before, after }) => {
			content = after.trim_start()
			space = after.drop_suffix(content)
			match Str.split_first(content.drop_prefix("<!--!"), "-->") {
				Ok({ before: marker, after: rest }) if content.starts_with("<!--!") and marker.count_utf8_bytes() <= 4 => "${before}${opening}${space}<!--!${marker}-->${intro(root)}${rest}"
				_ => document
			}
		}
		Err(_) => document
	}
}

intro = |root|
	Str.join_with(
		[
			"",
			"        <h1 class=\"pkg-full-name-heading\">${package_name}</h1>",
			"        <p>An ergonomic command-line argument parser for Roc: one record builder",
			"        gives typed data, help text, usage and actionable diagnostics.</p>",
			"        <p>Pick a module from the sidebar, or head back to the",
			"        <a href=\"${root}\">${package_name} manual</a> to get started.</p>",
			"",
		],
		"\n",
	)

manual_page = "<html><head>\n<title>The weaver manual</title>\n</head><body>\n<h1>Get started</h1>\n</body></html>\n"

module_page = "<html><head>\n<title>ANSI Docs</title>\n</head><body>\n<nav id=\"sidebar-nav\"><h1 class=\"pkg-full-name\"><a href=\"../\">package</a></h1>\n            <ul class=\"module-links\">\n</ul></nav>\n<div class=\"main-content\">\n<!--!x-->\n<h1>ANSI</h1></div>\n<footer><p>Made by people who like to make nice things.</p></footer>\n</body></html>\n"

index_page = "<html><head>\n<title>package Docs</title>\n</head><body class=\"docs-index\">\n<nav id=\"sidebar-nav\"><h1 class=\"pkg-full-name\"><a href=\"\">package</a></h1></nav>\n<div class=\"main-content\">\n<!--!x-->\n<p>index</p></div>\n</body></html>\n"

expect Html.root_of("index.html") == "./"
expect Html.root_of("main/index.html") == "../"
expect Html.root_of("0.13.0/ANSI/index.html") == "../../"
expect Html.enhance(manual_page, "index.html") == Ok(manual_page)
expect Html.enhance("<p>fragment</p>", "index.html") == Err(IncompletePage)
expect Html.enhance(module_page, "main/ANSI/index.html") == Ok("<html><head>\n<title>ANSI · weaver</title>\n    <link rel=\"stylesheet\" href=\"../../docs-site.css\">\n</head><body>\n<nav id=\"sidebar-nav\"><h1 class=\"pkg-full-name\"><a href=\"../\">weaver</a></h1>\n            <ul class=\"module-links\">\n                <li class=\"sidebar-entry sidebar-site-link\"><a href=\"../../\">← weaver manual</a></li>\n</ul></nav>\n<div class=\"main-content\">\n<!--!x-->\n<h1>ANSI</h1></div>\n<footer><p><a href=\"../../\">weaver</a> is open source under the UPL-1.0 license.</p></footer>\n</body></html>\n")
expect {
	enhanced = Html.enhance(index_page, "main/index.html")?
	enhanced.contains("<title>weaver API documentation</title>")
		and enhanced.contains("<a href=\".\">weaver</a></h1>")
		and enhanced.contains("<!--!x-->\n        <h1 class=\"pkg-full-name-heading\">weaver</h1>")
		and enhanced.contains("<a href=\"../\">weaver manual</a> to get started.</p>\n\n<p>index</p>")
}
expect Html.route("/") == Redirect("/weaver/") and Html.route("/weaver") == Redirect("/weaver/")
expect Html.route("/weaver/") == File(["index.html"])
expect Html.route("/weaver/main/ANSI/") == File(["main", "ANSI", "index.html"])
expect Html.route("/weaver/docs-site.css") == File(["docs-site.css"])
expect Html.route("/weaver/../secret") == NotFound and Html.route("/weaver/main/../../secret") == NotFound
expect Html.route("/weaver/.weaver-site") == NotFound and Html.route("/weaver//etc/passwd") == NotFound
expect Html.route("/other/") == NotFound and Html.route("/weaver/a\\b") == NotFound
