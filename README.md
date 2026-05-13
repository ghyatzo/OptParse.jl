<p align="center">
  <img src="docs/src/assets/logo.svg" alt="OptParse logo" width="420">
</p>

# OptParse.jl

A Type Stable Composable CLI Parser for Julia, inspired by [optparse-applicative](https://github.com/pcapriotti/optparse-applicative) and [Optique](https://optique.dev/).

[![Build Status](https://github.com/ghyatzo/OptParse.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/ghyatzo/OptParse.jl/actions/workflows/ci.yml)
[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)
[![Docs](https://img.shields.io/badge/docs-latest-blue.svg)](https://ghyatzo.github.io/OptParse.jl)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

> [!WARNING]
> **Work In Progress**: OptParse is in active development. The API is experimental and subject to frequent change.
> Type stability is tested and promising, but needs more real-world validation.

## Philosophy

The aim is to provide an argument parsing package for CLI apps that supports trimming.

In OptParse, everything is a parser. Complex parsers are built from simpler ones through composition.
Following the principle of "parse, don't validate," OptParse returns exactly what you ask for—or fails with a clear explanation.

Each parser is a tree of subparsers. Leaf nodes do the actual parsing, intermediate nodes compose and orchestrate parsers to
create new behaviours. Parsing is done in two passes:

- in the first, the input is checked against each branch of the tree until a match is found. Each node updates its state
to reflect if it succeded or not. This is the `parse` step.
- if the input match any of the branches we consider the step successful, otherwise we return the error of why it failed to match.
- the second pass is the `complete` step. The tree is collapsed, eventual validation error handled and a final value returned.

## Quick Start

```julia
using OptParse

# Define a parser
parser = record((
    name = option("-n", "--name", str("NAME")),
    port = option("-p", "--port", integer("PORT"; min=1000)),
    verbose = flag("-v", "--verbose")
))

# Parse arguments
result = optparse(parser, ["--name", "myserver", "-p", "8080", "-v"])

@assert result.name == "myserver"
@assert result.port == 8080
@assert result.verbose == true
```

The style implemented in this library is the following:

- short form names only accept single letters: `-n` is fine, `-run` will be treated as bundled `-r -u -n`.
- short form options must separate the flag from the value: `-n name`. No gcc style `-L/usr/include`.
- long form is represented with two dashes `--long`
- `--` means: from that point on, stop recognizing flags and options. Everything after it can be consumed by positional-style parsers.

For the public entrypoints:

- `optparse(parser, argv)` is the high-level convenience entrypoint
- `tryoptparse(parser, argv)` is the lower-level entrypoint and returns a result container instead of throwing
- `valuetype(parser)` returns the final value type produced by a parser

`optparse` has two modes controlled through the `juliac` key via
`Preferences.jl` mechanisms:

- in normal Julia runtime usage, it returns the parsed value or throws `OptParse.ParseException`
- when `juliac` mode is enabled, it renders the error to `stderr` and returns `nothing` on failure instead of throwing

If you need stable non-throwing behavior across environments, use `tryoptparse`.

## Core Concepts

OptParse provides four types of building blocks:

### Primitives

The fundamental parsers that match command-line tokens:

- **`option`** - Matches key-value pairs: `--port 8080` or `-p 8080`
- **`flag`** - Optional boolean flags like: `--verbose` or `-v`
- **`switch`** - Required presence flags used to guard a branch or feature
- **`arg`** - Positional arguments: `cp source destination`
- **`command`** - Subcommands: `git add file.txt`

```julia
# Options with different styles
port = option("-p", "--port", integer("PORT"))
result = optparse(port, ["--port=8080"])  # Long form with =
result = optparse(port, ["-p", "8080"])   # Short form

# Flags can be bundled
parser = record((
    all = switch("-a"),
    long = switch("-l"),
    human = switch("-h")
))
result = optparse(parser, ["-alh"])  # Equivalent to ["-a", "-l", "-h"]
```

### Value Parsers

Type-safe parsers that convert strings to values:

- **`str()`** - String values with optional pattern validation
- **`integer()`** / **`i8()`**, **`u32()`**, etc. - Integer types with min/max bounds
- **`flt()`** / **`flt32()`**, **`flt64()`** - Floating point numbers
- **`choice()`** - Enumerated values from a string list or `@enum` type
- **`uuid()`** - UUID validation
- **`path()`** - Existing filesystem paths

```julia
# Type-safe parsing with constraints
port = option("-p", integer("PORT"; min=1000, max=65535))
level = option("-l", choice("LEVEL", ["debug", "info", "warn", "error"]))
config = option("-c", str("FILE"; pattern=r".*\.toml$"))

@enum Mode begin
    Debug
    Release
end

mode = option("--mode", choice("MODE", Mode))
```

When you want a named placeholder in help or usage, prefer the positional metavar form:
`str("FILE")`, `integer("PORT")`, `choice("MODE", Mode)`. The `metavar=` keyword still works,
but the positional form is the main API.

### Modifiers

Enhance parsers with additional behavior:

- **`optional`** - Convenience wrapper for `default(p, nothing)`
- **`default`** - Provides a fallback value
- **`many`** / **`many1`** / **`repeated`** - Allows repeated matches, returns a vector
- **`help`** - Attaches help text to a parser
- **`hidden`** - Hides a parser from usage/help output while still parsing it

```julia
# Optional values
email = optional(option("-e", "--email", str("EMAIL")))

# With defaults
port = default(option("-p", integer("PORT")), 8080)

# Repeated values
packages = many(arg(str("PACKAGE")))  # pkg add Package1 Package2 Package3

# Verbosity levels
verbosity = many(switch("-v"))  # -v -v -v or -vvv

# One or more values
files = many1(arg(str("FILE")))

# Help annotations
serve = command("serve", record((
    host = option("--host", str("HOST")) |> help("Host", "Hostname to bind"),
    port = default(option("--port", integer("PORT")), 8080) |> help("Port", "TCP port to listen on"),
    verbose = flag("-v", "--verbose") |> help("Verbose", "Enable verbose logging"),
)))
```

`help(...)` does not change parsing semantics. It annotates the parser tree so
OptParse can derive richer usage/help output from the same definitions.

### Constructors

Compose parsers into complex structures:

- **`record`** - Named tuple of parsers (most common)
- **`or`** - Mutually exclusive alternatives (for subcommands)
- **`sequence`** - Ordered sequence of parsers (returns a tuple)
- **`combine`** / **`concat`** - Merge several parser groups

`or(...)` is order-dependent: branches are tried in the order they are listed, and the first semantic match wins. Put broader positional parsers like `arg(...)` or `many(arg(...))` last.

```julia
# Record composition
parser = record((
    input = arg(str("INPUT")),
    output = option("-o", "--output", str("OUTPUT")),
    force = flag("-f", "--force")
))

# Alternative commands with or
addCmd = command("add", record((
    action = @constant(:add),
    packages = many(arg(str("PACKAGE")))
)))

removeCmd = command("remove", record((
    action = @constant(:remove),
    packages = many(arg(str("PACKAGE")))
)))

pkgParser = or(addCmd, removeCmd)
```

## Complete Example

Here's a more realistic example showing subcommands:

```julia
using OptParse

# Shared options
commonOpts = record((
    verbose = flag("-v", "--verbose"),
    quiet = flag("-q", "--quiet")
))

# Add command
addCmd = command("add", combine(
    commonOpts,
    record((packages = many(arg(str("PACKAGE"))),))
))

# Remove command
removeCmd = command("remove", "rm", combine(
    commonOpts,
    record((
        all = flag("--all"),
        packages = many(arg(str("PACKAGE")))
    ))
))

# Instantiate command
instantiateCmd = command("instantiate", combine(
    commonOpts,
    record((
        manifest = flag("-m", "--manifest"),
        project = flag("-p", "--project")
    ))
))

# Complete parser
parser = or(addCmd, removeCmd, instantiateCmd)

# Usage examples:
# julia pkg.jl add DataFrames Plots -v
# julia pkg.jl remove --all -q
# julia pkg.jl instantiate --manifest
```

## Type Stability

OptParse is designed for type stability. The return type of your parser is fully determined at compile time:

```julia
parser = record((
    name = option("-n", str()),
    port = option("-p", integer())
))

# Return type: @NamedTuple{name::String, port::Int64}

parser = or(
    record((mode = @constant(:a), value = arg(integer()))),
    record((mode = @constant(:b), value = arg(str())))
)

# Return type: Union{@NamedTuple{mode::Val{:a}, ...}, @NamedTuple{mode::Val{:b}, ...}}
```

If you want to dispatch on parsed values, prefer constructing a named type with
`construct(...)`. `valuetype` is still useful when the parser result stays
anonymous:

```julia
greet = command("greet", record((
    cmd = @constant(:greet),
    name = option("-n", str("NAME")),
)))

const Greet = valuetype(greet)

handle(x::Greet) = println("hello $(x.name)")
```

## Application Entry Points And Automatic Help

OptParse now separates parser semantics from application-facing CLI behavior
more explicitly.

At the parser level:

- `tryoptparse(parser, argv)` returns a result container
- `optparse(parser, argv)` returns the parsed value or throws

For real command-line apps, there is also `runparse(parser, argv; ...)`, which
adds a small amount of CLI policy:

- lexical help flags such as `--help`
- an optional top-level positional help command
- customizable behavior for bare invocation through `on_empty`

```julia
parser = command("serve", record((
    host = option("--host", str("HOST")),
    port = default(option("--port", integer("PORT")), 8080),
)))

runparse(parser, ["--help"]; progname = "prog")
runparse(parser, []; progname = "prog", on_empty = ["help"])
```

The lower-level help API is still available when you want explicit control:

- `build_help_doc(parser, argv)`
- `generate_help(parser, argv; progname=...)`
- `print_help(io, parser, argv; progname=...)`

If you want positional help explicitly inside a parser tree, `helpcommand()`
parses invocations such as `help remote add` into a `HelpRequest`, which
`runparse` can interpret by rendering focused help from the original parser.

## Typed Parsers And Construction

Anonymous parser outputs are still central to OptParse, but there is now a more
complete story for constructing named application types.

The dynamic path is `construct(T, parser)`:

```julia
struct ServerConfig
    host::String
    port::Int
end

parser = construct(ServerConfig, record((
    host = option("--host", str("HOST")),
    port = option("--port", integer("PORT")),
)))
```

`construct` delegates to StructUtils. In normal Julia runtime, that means it
can use the full dynamic lifting machinery, including custom StructUtils
integration and parametric construction when that information can be recovered
at runtime.

For stricter matching and trimming-oriented code, OptParse also provides
`construct_exact(T, parser)`. This path requires exact shape agreement between
the parser output and the target type.

On top of that, `@parser` provides a concise typed workflow:

```julia
parser = @parser "Server configuration" Config begin
    "Hostname to bind"
    host = option("--host", str("HOST"))

    "TCP port"
    port = default(option("--port", integer("PORT")), 8080)
end "Used by the development server."
```

The macro derives struct field types from the parser expressions themselves via
`valuetype(...)`, so the typed definition stays aligned with the parser output.

That gives OptParse three useful layers:

- anonymous composition with `record(...)` and `sequence(...)`
- dynamic lifting with `construct(...)`
- exact, trim-friendly typed construction with `construct_exact(...)` and `@parser`

## Error Handling

OptParse exposes two entrypoints:

```julia
parser = option("-p", integer(min=1000))

# Throwing API
value = optparse(parser, ["-p", "3000"])

# Lower-level API
result = tryoptparse(parser, ["-p", "3000"])
```

`optparse` returns the parsed value on success and throws `OptParse.ParseException` on failure.
`tryoptparse` returns a result container instead of throwing, which is useful if you want to inspect failures programmatically.

Rendered error messages are produced centrally from structured internal diagnostics. The exact wording may evolve, but failures are surfaced with parser-specific context, for example invalid values, missing required inputs, or unexpected arguments. In the high-level `optparse` path, the rendered exception also appends a focused usage line derived from the parser tree.

```julia
parser = option("-p", integer(min=1000))

try
    optparse(parser, ["-p", "abc"])
catch err
    @assert err isa OptParse.ParseException
end
```

## Installation

```julia
using Pkg
Pkg.add("OptParse")
```

## Documentation

Comprehensive documentation is available through Julia's help system:

```jlrepl
julia> using OptParse

julia> ?option
julia> ?record
julia> ?or
```

For more detailed documentation, see the [Documentation](https://ghyatzo.github.io/OptParse.jl).

Additionally, the [Optique's excellent documentation website](https://optique.dev/) or docs from the great [optparse-applicative](https://github.com/pcapriotti/optparse-applicative), might be of interest for more in depth analysis or phylosophy. There are some differences but the core concepts are the same since both have been an inspiration on the design of this library.

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

MIT License. See [LICENSE](LICENSE) for details.

## Acknowledgments

- [optparse-applicative](https://github.com/pcapriotti/optparse-applicative) - Haskell command-line parser
- [Optique](https://optique.dev/) - Typescript CLI parsing library
