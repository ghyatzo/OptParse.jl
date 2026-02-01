# OptParse

A Type Stable Composable CLI Parser for Julia, inspired by [optparse-applicative](https://github.com/pcapriotti/optparse-applicative) and [Optique](https://optique.dev/) (typescript version).

[![Build Status](https://github.com/ghyatzo/OptParse/workflows/CI/badge.svg)](https://github.com/ghyatzo/OptParse/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

> ⚠️ **Work In Progress**: OptParse is in active development. The API is experimental and subject to frequent change.
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
- the second pass is the `complete` step. The tree is collapsed, eventual validation error handled and a final object (or error) returned.

## Missing Features:

- [ ] automatic usage and help printing
- [ ] more value parsers (like, dates, paths, uri...)
- [ ] `map` modifier, unfortunately until julia has something like `TypedCallabe`s it's impossible to
ensure type stability with arbitrary functions.
- [ ] `longest-match` combinator (maybe, still debating utility)
- [ ] `group` combinator: light simple parser useful only for enclosing multiple parsers together in the same category. mainly useful for help messages.
- [ ] automatic suggestions / shell completions
- [ ] better error handling: proper exceptions with richer metadata instead of plain strings.

## Quick Start

```julia
using OptParse

# Define a parser
parser = object((
    name = option("-n", "--name", str()),
    port = option("-p", "--port", integer(min=1000)),
    verbose = switch("-v", "--verbose")
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

## Core Concepts

OptParse provides four types of building blocks:

### Primitives

The fundamental parsers that match command-line tokens:

- **`option`** - Matches key-value pairs: `--port 8080` or `-p 8080`
- **`flag`** - Boolean flags like: `--verbose` or `-v`. A plain `flag` MUST be present. See `switch` for a flag that is false if not passed.
- **`argument`** - Positional arguments: `cp source destination`
- **`command`** - Subcommands: `git add file.txt`

```julia
# Options with different styles
port = option("-p", "--port", integer())
result = argparse(port, ["--port=8080"])  # Long form with =
result = argparse(port, ["-p", "8080"])   # Short form

# Flags can be bundled
parser = object((
    all = flag("-a"),
    long = flag("-l"),
    human = flag("-h")
))
result = argparse(parser, ["-alh"])  # Equivalent to ["-a", "-l", "-h"]
```

### Value Parsers

Type-safe parsers that convert strings to values:

- **`str()`** - String values with optional pattern validation
- **`integer()`** / **`i8()`**, **`u32()`**, etc. - Integer types with min/max bounds
- **`flt()`** / **`flt32()`**, **`flt64()`** - Floating point numbers
- **`choice()`** - Enumerated values
- **`uuid()`** - UUID validation

```julia
# Type-safe parsing with constraints
port = option("-p", integer(min=1000, max=65535))
level = option("-l", choice("debug", "info", "warn", "error"))
config = option("-c", str(pattern=r".*\.toml$"))
```

### Modifiers

Enhance parsers with additional behavior:

- **`optional`** - Makes a parser optional (returns `nothing` if absent)
- **`withDefault`** - Provides a fallback value
- **`multiple`** - Allows repeated matches, returns a vector

```julia
# Optional values
email = optional(option("-e", "--email", str()))

# With defaults
port = withDefault(option("-p", integer()), 8080)

# Multiple values
packages = multiple(argument(str()))  # pkg add Package1 Package2 Package3

# Verbosity levels
verbosity = multiple(flag("-v"))  # -v -v -v or -vvv
```

### Constructors

Compose parsers into complex structures:

- **`object`** - Named tuple of parsers (most common)
- **`or`** - Mutually exclusive alternatives (for subcommands)
- **`tup`** - Ordered tuple (preserves parser order)
- **`objmerge`** / **`concat`** - Merge multiple parser groups

```julia
# Object composition
parser = object((
    input = argument(str(metavar="INPUT")),
    output = option("-o", "--output", str()),
    force = switch("-f", "--force")
))

# Alternative commands with or
addCmd = command("add", object((
    action = @constant(:add),
    packages = multiple(argument(str()))
)))

removeCmd = command("remove", object((
    action = @constant(:remove),
    packages = multiple(argument(str()))
)))

pkgParser = or(addCmd, removeCmd)
```

## Complete Example

Here's a more realistic example showing subcommands:

```julia
using OptParse

# Shared options
commonOpts = object((
    verbose = switch("-v", "--verbose"),
    quiet = switch("-q", "--quiet")
))

# Add command
addCmd = command("add", objmerge(
    commonOpts,
    object((packages = multiple(argument(str(metavar="PACKAGE"))),))
))

# Remove command
removeCmd = command("remove", "rm", objmerge(
    commonOpts,
    object((
        all = switch("--all"),
        packages = multiple(argument(str(metavar="PACKAGE")))
    ))
))

# Instantiate command
instantiateCmd = command("instantiate", objmerge(
    commonOpts,
    object((
        manifest = switch("-m", "--manifest"),
        project = switch("-p", "--project")
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

# Return type: @NamedTuple{name::String, port::Int64)}

parser = or(
    object((mode = @constant(:a), value = argument(integer()))),
    object((mode = @constant(:b), value = argument(str())))
)

# Return type: Union{@NamedTuple{mode::Val{:a}, ...}, @NamedTuple{mode::Val{:b}, ...}}
```

## Error Handling

When parsing fails, OptParse provides clear error messages indicating what went wrong:

```julia
parser = option("-p", integer(min=1000))

# Invalid value
argparse(parser, ["-p", "abc"])  # Error: Expected integer

# Out of range
argparse(parser, ["-p", "500"])  # Error: Value must be >= 1000

# Missing required option
argparse(parser, [])  # Error: Required option -p not found
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

For more detailed documentation, see [Optique's excellent documentation website](https://optique.dev/),
which heavily influenced this package API. There are some minor differences but the core concepts are the same since both are inspired by
the great [optparse-applicative](https://github.com/pcapriotti/optparse-applicative).

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

MIT License. See [LICENSE](LICENSE) for details.

## Acknowledgments

- [optparse-applicative](https://github.com/pcapriotti/optparse-applicative) - Haskell command-line parser
- [Optique](https://optique.dev/) - Typescript CLI parsing library
