import cli.Path

## Deterministic filesystem discovery helpers for repository scripts.
Files := [].{

	## List the `.roc` files immediately inside `directory`, sorted by name.
	direct_roc_files! : Path => Try(List(Path), _)
	direct_roc_files! = |directory| {
		entries = Path.list!(directory)?
		Ok(sort_paths(entries.keep_if(|path| Path.ext(path).map_ok(Path.display) == Ok("roc"))))
	}

	## Recursively list the `.roc` files under `directory`, sorted by path.
	all_roc_files! : Path => Try(List(Path), _)
	all_roc_files! = |directory| all_files_with_ext!(directory, "roc")

	## Recursively list the files under `directory` with the extension `ext`,
	## sorted by path.
	all_files_with_ext! : Path, Str => Try(List(Path), _)
	all_files_with_ext! = |directory, ext| Ok(sort_paths(walk!(Path.list!(directory)?, ext, [])?))

	## The final component of a path, for display and for building sibling names.
	name : Path -> Str
	name = |path|
		match Path.filename(path) {
			Ok(filename) => Path.display(filename)
			Err(_) => Path.display(path)
		}

	## Return the part of a filename before its first dot.
	stem : Str -> Str
	stem = |filename|
		match Str.split_on(filename, ".") {
			[first, ..] => first
			[] => filename
		}

	## Sort paths bytewise by their display form.
	sort_paths : List(Path) -> List(Path)
	sort_paths = |paths|
		paths
			.map(|path| (Str.to_utf8(Path.display(path)), path))
			.sort_with(|(left, _), (right, _)| compare_bytes(left, right))
			.map(|(_, path)| path)
}

walk! = |entries, ext, found|
	match entries {
		[] => Ok(found)
		[path, .. as rest] =>
			match Path.type!(path)? {
				IsDir => walk!(rest, ext, walk!(Path.list!(path)?, ext, found)?)
				IsFile if Path.ext(path).map_ok(Path.display) == Ok(ext) => walk!(rest, ext, found.append(path))
				_ => walk!(rest, ext, found)
			}
	}

compare_bytes = |left, right|
	match (left, right) {
		([a, .. as left_rest], [b, .. as right_rest]) =>
			if a < b LT else if a > b GT else compare_bytes(left_rest, right_rest)
		([], []) => EQ
		([], _) => LT
		(_, []) => GT
	}
