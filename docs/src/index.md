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
- the second pass is the `complete` step. The tree is collapsed, eventual validation error handled and a final object returned.

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

Current parsing conventions:

- short option names are single-letter only
- short options must separate the flag from the value: `-n value`
- long options use the `--long` form
- `--` means: from that point on, stop recognizing flags and options. Everything after it can be consumed by positional-style parsers

For the public entrypoints:

- `optparse(parser, argv)` is the high-level convenience entrypoint
- `tryoptparse(parser, argv)` is the lower-level entrypoint and returns a result object instead of throwing
- `resulttype(parser)` returns the final value type produced by a parser

`optparse` has two modes controlled through the `juliac` key via
`Preferences.jl` mechanisms:

- in normal Julia runtime usage, it returns the parsed value or throws `OptParse.ParseException`
- when `juliac` mode is enabled, it renders the error to `stderr` and returns `nothing` on failure instead of throwing

If you need stable non-throwing behavior across environments, use `tryoptparse`.

## Core Concepts

OptParse provides four types of building blocks that compose together to create powerful CLI parsers:

### Primitives

The fundamental parsers that match command-line tokens:

- [`option`](@ref) - Matches key-value pairs: `--port 8080` or `-p 8080`
- [`flag`](@ref) - Optional boolean flags that default to `false`
- [`gate`](@ref) - Required presence flags: `--experimental` or `-x`
- [`arg`](@ref) - Positional arguments: `source destination`
- [`command`](@ref) - Subcommands: `git add file.txt`
- [`@constant`](@ref) - Always returns a constant value

### Value Parsers

Type-safe parsers that convert strings to values:

- [`str`](@ref) - String values with optional pattern validation
- [`integer`](@ref) / [`i8`](@ref), [`u32`](@ref), etc. - Integer types with min/max bounds
- [`flt`](@ref) / [`flt32`](@ref), [`flt64`](@ref) - Floating point numbers
- [`choice`](@ref) - Enumerated values from a string list or `@enum` type
- [`uuid`](@ref) - UUID validation
- [`path`](@ref) - Existing filesystem paths

When you want a named placeholder in help or usage, prefer the positional metavar form:
`str("FILE")`, `integer("PORT")`, `choice("MODE", Mode)`. The `metavar=` keyword still works,
but the positional form is the main API.

The full constructor reference for value parsers is listed in the [API reference](reference.md).

### Modifiers

Enhance parsers with additional behavior:

- [`optional`](@ref) - Convenience wrapper for `default(p, nothing)`
- [`default`](@ref) - Provides a fallback value
- [`many`](@ref) / [`many1`](@ref) / [`repeated`](@ref) - Allows repeated matches, returns a vector
- [`help`](@ref) - Attaches help text to a parser without changing parsing semantics
- [`hidden`](@ref) - Hides a parser from usage/help output without changing parsing semantics

Help annotations compose directly with normal parsers:

```julia
parser = command("serve", object((
    host = option("--host", str("HOST")) |> help("Host", "Hostname to bind"),
    port = default(option("--port", integer("PORT")), 8080) |> help("Port", "TCP port to listen on"),
    verbose = flag("-v", "--verbose") |> help("Verbose", "Enable verbose logging"),
)))
```

Those annotations do not change how parsing works. They are used when OptParse
renders usage and high-level parse failures.

### Constructors

Compose parsers into complex structures:

- [`object`](@ref) - Named tuple of parsers (most common)
- [`or`](@ref) - Mutually exclusive alternatives (for subcommands)
- [`sequence`](@ref) - Ordered sequence of parsers (returns a tuple)
- [`combine`](@ref) / [`concat`](@ref) - Merge several parser groups

`or(...)` is order-dependent: branches are tried in the order they are listed, and the first semantic match wins. Put broader positional parsers like `arg(...)` or `many(arg(...))` last.

### Complete Application Example

Here's a more realistic example showing a package manager-style CLI:

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
    object((packages = many(arg(str("PACKAGE"))),))
))

# Remove command
removeCmd = command("remove", "rm", combine(
    commonOpts,
    object((
        all = flag("--all"),
        packages = many(arg(str("PACKAGE")))
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
    object((mode = @constant(:a), value = integer())),
    object((mode = @constant(:b), value = str()))
)

# Return type: Union{@NamedTuple{mode::Val{:a}, ...}, NamedTuple{mode::Val{:b}, ...}}
```

This means that Julia's compiler can optimize your parsing code effectively, and you get better performance
and compile-time guarantees about the structure of your parsed results.

When you want to dispatch on the result of a specific parser, use
[`resulttype`](@ref):

```julia
greet = command("greet", object((
    cmd = @constant(:greet),
    name = option("-n", str("NAME")),
)))

const Greet = resulttype(greet)

handle(x::Greet) = println("hello $(x.name)")
```

## Error Handling

OptParse exposes two entrypoints:

```julia
parser = option("-p", integer("PORT"; min=1000))

# Throwing API
value = optparse(parser, ["-p", "3000"])

# Lower-level API
result = tryoptparse(parser, ["-p", "3000"])
```

`optparse` returns the parsed value on success and throws `OptParse.ParseException` on failure.
`tryoptparse` returns a result object instead of throwing, which is useful if you want to inspect failures programmatically.

Rendered error messages are produced centrally from structured internal diagnostics. The exact wording may evolve, but failures are surfaced with parser-specific context, for example invalid values, missing required inputs, or unexpected arguments.
In the high-level `optparse` path, the exception renderer also appends a focused
usage line derived from the parser tree.

```julia
parser = option("-p", integer("PORT"; min=1000))

try
    optparse(parser, ["-p", "abc"])
catch err
    @assert err isa OptParse.ParseException
end
```

## Internals

If you want to understand the parser runtime or contribute a new parser family or
value parser, see the [development guide](development/index.md).


## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests on
[GitHub](https://github.com/ghyatzo/OptParse).

## Acknowledgments

OptParse's design is inspired by:
- [Optique](https://optique.dev/) - Typescript CLI parsing library with similar composable design
- [optparse-applicative](https://github.com/pcapriotti/optparse-applicative) - Haskell command-line parser that pioneered this approach

## License

OptParse is released under the [MIT License](https://github.com/ghyatzo/OptParse/blob/main/LICENSE).
