# OptParse

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
- the second pass is the `complete` step. The tree is collapsed, eventual validation error handled and a final object returned.

## Missing Features:

- [ ] automatic usage and help printing
- [ ] more value parsers (like dates, URIs, date-times...)
- [ ] `map` modifier, unfortunately until julia has something like `TypedCallabe`s it's impossible to
ensure type stability with arbitrary functions.
- [ ] `longest-match` combinator
- [ ] `group` combinator: light simple parser useful only for enclosing multiple parsers together in the same category. mainly useful for help messages.
- [ ] automatic suggestions / shell completions
- [x] polish and stabilize the public error-reporting interface

## Quick Start

```julia
using OptParse

# Define a parser
parser = object((
    name = option("-n", "--name", str("NAME")),
    port = option("-p", "--port", integer("PORT"; min=1000)),
    verbose = flag("-v", "--verbose")
))

# Parse arguments
result = argparse(parser, ["--name", "myserver", "-p", "8080", "-v"])

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

- `argparse(parser, argv)` is the high-level convenience entrypoint
- `tryargparse(parser, argv)` is the lower-level entrypoint and returns a result object instead of throwing

`argparse` currently has a build-time split:

- in normal Julia runtime usage, it returns the parsed value or throws `OptParse.ParseException`
- when compiled while `Base.generating_output()` is true (for example in the current trimming workflow), it renders the error to `stderr` and returns `nothing` on failure instead of throwing

If you need stable non-throwing behavior across environments, use `tryargparse`.

## Core Concepts

OptParse provides four types of building blocks:

### Primitives

The fundamental parsers that match command-line tokens:

- **`option`** - Matches key-value pairs: `--port 8080` or `-p 8080`
- **`flag`** - Optional boolean flags like: `--verbose` or `-v`
- **`gate`** - Required presence flags used to guard a branch or feature
- **`arg`** - Positional arguments: `cp source destination`
- **`command`** - Subcommands: `git add file.txt`

```julia
# Options with different styles
port = option("-p", "--port", integer("PORT"))
result = argparse(port, ["--port=8080"])  # Long form with =
result = argparse(port, ["-p", "8080"])   # Short form

# Flags can be bundled
parser = object((
    all = gate("-a"),
    long = gate("-l"),
    human = gate("-h")
))
result = argparse(parser, ["-alh"])  # Equivalent to ["-a", "-l", "-h"]
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
- **`multiple`** - Allows repeated matches, returns a vector

```julia
# Optional values
email = optional(option("-e", "--email", str("EMAIL")))

# With defaults
port = default(option("-p", integer("PORT")), 8080)

# Multiple values
packages = multiple(arg(str("PACKAGE")))  # pkg add Package1 Package2 Package3

# Verbosity levels
verbosity = multiple(gate("-v"))  # -v -v -v or -vvv
```

### Constructors

Compose parsers into complex structures:

- **`object`** - Named tuple of parsers (most common)
- **`or`** - Mutually exclusive alternatives (for subcommands)
- **`sequence`** - Ordered sequence of parsers (returns a tuple)
- **`combine`** / **`concat`** - Merge multiple parser groups

`or(...)` is order-dependent: branches are tried in the order they are listed, and the first semantic match wins. Put broader positional parsers like `arg(...)` or `multiple(arg(...))` last.

```julia
# Object composition
parser = object((
    input = arg(str("INPUT")),
    output = option("-o", "--output", str("OUTPUT")),
    force = flag("-f", "--force")
))

# Alternative commands with or
addCmd = command("add", object((
    action = @constant(:add),
    packages = multiple(arg(str("PACKAGE")))
)))

removeCmd = command("remove", object((
    action = @constant(:remove),
    packages = multiple(arg(str("PACKAGE")))
)))

pkgParser = or(addCmd, removeCmd)
```

## Complete Example

Here's a more realistic example showing subcommands:

```julia
using OptParse

# Shared options
commonOpts = object((
    verbose = flag("-v", "--verbose"),
    quiet = flag("-q", "--quiet")
))

# Add command
addCmd = command("add", combine(
    commonOpts,
    object((packages = multiple(arg(str("PACKAGE"))),))
))

# Remove command
removeCmd = command("remove", "rm", combine(
    commonOpts,
    object((
        all = flag("--all"),
        packages = multiple(arg(str("PACKAGE")))
    ))
))

# Instantiate command
instantiateCmd = command("instantiate", combine(
    commonOpts,
    object((
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
parser = object((
    name = option("-n", str()),
    port = option("-p", integer())
))

# Return type: @NamedTuple{name::String, port::Int64}

parser = or(
    object((mode = @constant(:a), value = arg(integer()))),
    object((mode = @constant(:b), value = arg(str())))
)

# Return type: Union{@NamedTuple{mode::Val{:a}, ...}, @NamedTuple{mode::Val{:b}, ...}}
```

## Error Handling

OptParse exposes two entrypoints:

```julia
parser = option("-p", integer(min=1000))

# Throwing API
value = argparse(parser, ["-p", "3000"])

# Lower-level API
result = tryargparse(parser, ["-p", "3000"])
```

`argparse` returns the parsed value on success and throws `OptParse.ParseException` on failure.
`tryargparse` returns a result object instead of throwing, which is useful if you want to inspect failures programmatically.

Rendered error messages are produced centrally from structured internal diagnostics. The exact wording may evolve, but failures are surfaced with parser-specific context, for example invalid values, missing required inputs, or unexpected arguments.

```julia
parser = option("-p", integer(min=1000))

try
    argparse(parser, ["-p", "abc"])
catch err
    @assert err isa OptParse.ParseException
end
```

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/ghyatzo/OptParse")
```

## Documentation

Comprehensive documentation is available through Julia's help system:

```jlrepl
julia> using OptParse

julia> ?option
julia> ?object
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
