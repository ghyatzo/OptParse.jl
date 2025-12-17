# OptParse.jl

*A Type Stable Composable CLI Parser for Julia*

OptParse is a command-line argument parser that emphasizes composability, type stability, and clarity.
Heavily inspired by [Optique](https://optique.dev/) and [optparse-applicative](https://github.com/pcapriotti/optparse-applicative),
OptParse allows you to build complex argument parsers from simple, reusable components.

!!! warning "Work In Progress"
    OptParse is in active development. The API is experimental and subject to change.
    Type stability is tested and promising, but needs more real-world validation.

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

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/ghyatzo/OptParse")
```

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

## Core Concepts

OptParse provides four types of building blocks that compose together to create powerful CLI parsers:

### Primitives

The fundamental parsers that match command-line tokens:

- [`option`](@ref) - Matches key-value pairs: `--port 8080` or `-p 8080`
- [`flag`](@ref) - Boolean switches: `--verbose` or `-v`
- [`switch`](@ref) - Optional flags that default to `false`
- [`argument`](@ref) - Positional arguments: `source destination`
- [`command`](@ref) - Subcommands: `git add file.txt`
- [`@constant`](@ref) - Always returns a constant value

### Value Parsers

Type-safe parsers that convert strings to values:

- `str()` - String values with optional pattern validation
- `integer()` / `i8()`, `u32()`, etc. - Integer types with min/max bounds
- `flt()` / `flt32()`, `flt64()` - Floating point numbers
- `choice()` - Enumerated values
- `uuid()` - UUID validation

### Modifiers

Enhance parsers with additional behavior:

- [`optional`](@ref) - Makes a parser optional (returns `nothing` if absent)
- [`withDefault`](@ref) - Provides a fallback value
- [`multiple`](@ref) - Allows repeated matches, returns a vector

### Constructors

Compose parsers into complex structures:

- [`object`](@ref) - Named tuple of parsers (most common)
- [`or`](@ref) - Mutually exclusive alternatives (for subcommands)
- [`tup`](@ref) - Ordered tuple (preserves parser order)
- [`objmerge`](@ref) / [`concat`](@ref) - Merge multiple parser groups

### Complete Application Example

Here's a more realistic example showing a package manager-style CLI:

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
    object((mode = @constant(:a), value = integer())),
    object((mode = @constant(:b), value = str()))
)

# Return type: Union{@NamedTuple{mode::Val{:a}, ...}, NamedTuple{mode::Val{:b}, ...}}
```

This means that Julia's compiler can optimize your parsing code effectively, and you get better performance
and compile-time guarantees about the structure of your parsed results.

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


## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests on
[GitHub](https://github.com/ghyatzo/OptParse).

## Acknowledgments

OptParse's design is heavily inspired by:
- [Optique](https://optique.dev/) - Typescript CLI parsing library with similar composable design
- [optparse-applicative](https://github.com/pcapriotti/optparse-applicative) - Haskell command-line parser that pioneered this approach

## License

OptParse is released under the [MIT License](https://github.com/ghyatzo/OptParse/blob/main/LICENSE).