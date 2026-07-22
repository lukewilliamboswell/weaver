[![Roc-Lang][roc_badge]][roc_link]

[roc_badge]: https://img.shields.io/endpoint?url=https%3A%2F%2Fpastebin.com%2Fraw%2FcFzuCCd7
[roc_link]: https://github.com/roc-lang/roc

Weaver
======

An ergonomic command-line argument parser for the Roc language.

This library aims to provide a convenient interface for parsing CLI arguments
into structured data, in the style of Rust's [clap](https://github.com/clap-rs/clap).
Without code generation at compile time, the closest we can get in Roc is the use of the
[record builder syntax](https://www.roc-lang.org/examples/RecordBuilder/README.html).
This allows us to build our config and parser at the same time, in a type-safe way.

Read the documentation at <https://lukewilliamboswell.github.io/weaver/Cli/>.

## Status

This library is ready to parse your args today, but I'm always looking for more testing
from the community! Feel free to open a GitHub issue if there's a feature you're missing
from another CLI parsing library that you think would fit well in Weaver.

## Example

```roc
app [main!] {
    pf: platform "https://github.com/lukewilliamboswell/roc-platform-template-zig/releases/download/1.0.0/AnZoxzoGPtSGQ15EQh6pBeeaHJ7aizP9MQhK81dES3Uq.tar.zst",
    weaver: "<latest from https://github.com/lukewilliamboswell/weaver/releases>",
}

import pf.Stdout
import weaver.Cli
import weaver.Opt
import weaver.Param

BasicConfig : {
    alpha : U64,
    force : Bool,
    file : Try(Str, [NoValue]),
    files : List(Str),
}

main! : List(Str) => Try({}, _)
main! = |args| {
    # This legacy platform includes the executable path in `args`.
    match Cli.parse_or_display_message(cli_parser, args.drop_first(1), str_to_raw_arg) {
        Err(Help(message)) => {
            Stdout.line!(message)?
            Ok({})
        }

        Err(Version(message)) => {
            Stdout.line!(message)?
            Ok({})
        }

        Err(InvalidUsage(message)) => {
            Stdout.line!(message)?
            Err(Exit(1))
        }

        Ok(data) => {
            Stdout.line!("Successfully parsed! Here's what I got:")?
            Stdout.line!("")?
            Stdout.line!(Str.inspect(data))?

            Ok({})
        }
    }
}

cli_parser : Cli.CliParser(BasicConfig)
cli_parser =
    Cli.assert_valid(
        Cli.finish(
            {
                alpha: Opt.u64({
                    short: "a",
                    long: "",
                    help: "Set the alpha level.",
                    default: NoDefault,
                }),
                force: Opt.flag({
                    short: "f",
                    long: "",
                    help: "Force the task to complete.",
                }),
                file: Param.maybe_str({
                    name: "file",
                    help: "The file to process.",
                }),
                files: Param.str_list({
                    name: "files",
                    help: "The rest of the files.",
                }),
            }.Cli,
            {
                name: "basic",
                version: "v0.1.0",
                authors: ["Some One <some.one@mail.com>"],
                description: "This is a basic example of what you can build with Weaver. You get safe parsing, useful error messages, and help pages all for free!",
                text_style: Plain,
            },
        ),
    )

str_to_raw_arg : Str -> [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]
str_to_raw_arg = |arg| UnixBytes(Str.to_utf8(arg))
```

And here's us calling the above example from the command line:

```console
$ roc examples/basic.roc -- file1.txt file2.txt -f -a 123
Successfully parsed! Here's what I got:

{ alpha: 123, file: Ok("file1.txt"), files: ["file2.txt"], force: True }

$ roc examples/basic.roc -- --help
basic v0.1.0
Some One <some.one@mail.com>

This is a basic example of what you can build with Weaver. You get safe parsing, useful error messages, and help pages all for free!

Usage:
  basic -a NUM [OPTIONS] [<file>] [<files>...]

Arguments:
  <file>      The file to process.
  <files...>  The rest of the files.

Options:
  -a NUM         Set the alpha level.
  -f             Force the task to complete.
  -h, --help     Show this help page.
  -V, --version  Show the version.
```

Weaver parses exactly the arguments passed to `Cli.parse_or_display_message`; it
never implicitly drops the first element. The example platform supplies `List(Str)`
including the executable path, so the example drops that element explicitly and its
legacy adapter preserves the underlying argument bytes. Modern platforms such as
`basic-cli` supply `List(OsStr)`; pass `OsStr.to_raw` directly to preserve UTF-8,
native Unix bytes, and Windows UTF-16 code units at Weaver's `Path` boundary. Only
drop the first element when the platform documents that it is the executable path.

Use `Opt.arg` or `Param.arg` when you want to keep the raw value as a
[`path.Path`](https://github.com/roc-lang/path/releases/tag/3.0.0-rc1). String
parsers such as `Opt.str` and `Param.str` intentionally decode at the parser
boundary without losing path-specific semantics in the raw parsers.

A separate token beginning with `-` is treated as another option, not as an option
value. Pass an option-like value with `--name=value`, or place `--` before the value;
for example, both `--beta=-2.5` and `--beta -- -2.5` are unambiguous.

There are also some examples in the [examples](./examples) directory that are more
feature-complete, with more to come as this library matures.

## Testing

Run the complete package and example suite with:

```sh
python3 scripts/test.py
```

The runner formats, checks, tests, documents, and bundles the package; then it
formats, checks, tests, and builds every example against that bundle. Each built
example is exercised with the cases in [`scripts/test_spec.json`](./scripts/test_spec.json),
including successful parses, help and version output, malformed values, missing
arguments, unknown options, nested subcommands, delimiters, and raw non-UTF-8
arguments on Unix. Every example must have a spec entry, so adding an example
without test cases fails the suite.

## Roadmap

Now that an initial release has happened, these are some ideas I have for future development:

- [ ] Optionally set `group : Str` per option so they are visually grouped in the help page
- [ ] Completion generation for popular shells (e.g. Bash, Zsh, Fish, etc.)
- [X] Add terminal escape sequences to generated messages for prettier help/usage text formatting (currently working, but could be nicer/more configurable)
- [ ] add convenient CLI platform wrappers (e.g. parse, or print help and exit) for use with module params
- [X] Clean up default parameter code if we can elide different fields on the same record type in different places (not currently allowed)
- [ ] Add more testing (always)
