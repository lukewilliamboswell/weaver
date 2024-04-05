roclap
======

A roc command-line argument parser (name pending).

This library aims to provide a convenient interface for parsing CLI arguments
into structured data, in the style of Rust's [clap](https://github.com/clap-rs/clap).
Without code generation at compile time, the closest we can get in Roc is the use of the
[record builder syntax](https://www.roc-lang.org/examples/RecordBuilder/README.html).
This allows us to build our config and parse at the same time, in a type-safe way!

## Example

```roc
expect
    parser =
        cliBuilder {
            alpha: <- numOption { short: "a" },
            beta: <- flagOption { short: "b", long: "--beta" },
            xyz: <- strOption { long: "xyz" },
            verbosity: <- occurrenceOption { short: "v", long: "--verbose" },
        }
        |> getParser

    out = parser ["app", "-a", "123", "-b", "--xyz", "some_text", "-vvvv"]

    out == Ok { alpha: 123, beta: Bool.true, xyz: "some_text", verbosity: 4 }
```

There are also some examples in the [examples](./examples) directory that are more feature-complete
more to come as this library matures.

## Roadmap

This library is a work-in-progress, but should be ready for usage in the next week or so!
These are the main things I want to work on:

- [X] simply-implemented support for optional args/lists of args
- [ ] full documentation of the library's features
- [ ] multiple documented and tested examples
- [ ] automatic help text generation
- [ ] subcommands, as simple as possible
- [X] choice args that select an option from a custom enum
- [ ] add more testing

### Long-Term Goals

- [ ] add convenient `Task` helpers (e.g. parse or print help and exit) once [module params](https://docs.google.com/document/u/0/d/110MwQi7Dpo1Y69ECFXyyvDWzF4OYv1BLojIm08qDTvg) land
- [ ] Completion generation for popular shells
- [ ] Clean up default parameter code if we can elide different fields on the same record type in different places (not currently allowed)
