import Text

## Pure repository-layout rules that the check script enforces.
StaticChecks := [].{

	## Problems with compiler pins. The package compiler floats and Blueprint.lock
	## is the only authority for the tooling compiler, so neither a `.roc-version`
	## file nor a `roc` header field may exist.
	pin_problems : Bool, List({ path : Str, source : Str }) -> List(Str)
	pin_problems = |roc_version_exists, sources| {
		version_file = if roc_version_exists [".roc-version must not exist: the package compiler is not pinned"] else []
		version_file.concat(
			sources
				.keep_if(|file| !Text.dependency_values(file.source, "roc").is_empty())
				.map(|file| "${file.path}: no header may pin a compiler with a roc field"),
		)
	}

	## Problems with example headers. Repository examples exercise the working
	## tree, so each names the package by its relative path.
	example_problems : List({ path : Str, source : Str }) -> List(Str)
	example_problems = |examples|
		examples
			.keep_if(|file| Text.dependency_values(file.source, "weaver") != ["../package/main.roc"])
			.map(|file| "${file.path}: the weaver dependency must be \"../package/main.roc\"")
}

expect StaticChecks.pin_problems(Bool.False, [{ path: "a.roc", source: "app [main!] {\n\tcli: platform \"u\",\n}\n" }]) == []
expect StaticChecks.pin_problems(Bool.True, []) == [".roc-version must not exist: the package compiler is not pinned"]
expect StaticChecks.pin_problems(Bool.False, [{ path: "a.roc", source: "app [main!] {\n\troc: \"nightly-1\",\n}\n" }]) == ["a.roc: no header may pin a compiler with a roc field"]
expect StaticChecks.example_problems([{ path: "e.roc", source: "\tweaver: \"../package/main.roc\",\n" }]) == []
expect StaticChecks.example_problems([{ path: "e.roc", source: "\tweaver: \"https://example.com/x.tar.zst\",\n" }]) == ["e.roc: the weaver dependency must be \"../package/main.roc\""]
expect StaticChecks.example_problems([{ path: "e.roc", source: "app [main!] {}\n" }]) == ["e.roc: the weaver dependency must be \"../package/main.roc\""]
