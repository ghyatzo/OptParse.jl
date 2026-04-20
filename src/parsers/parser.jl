abstract type AbstractParser{T, S, p, P} end

tval(::Type{<:AbstractParser{T}}) where {T} = T
tval(::AbstractParser{T}) where {T} = T

tstate(::Type{<:AbstractParser{T, S}}) where {T, S} = S
tstate(::AbstractParser{T, S}) where {T, S} = S

function priority(::Type{<:AbstractParser{T, S, _p}})::Int where {T, S, _p}
    return _p
end
function priority(::AbstractParser{T, S, _p})::Int where {T, S, _p}
    return _p
end

ptypes(::Type{<:AbstractParser{T, S, _p, P}}) where {T, S, _p, P} = P
ptypes(::AbstractParser{T, S, _p, P}) where {T, S, _p, P} = P

"""
    resulttype(parser_or_type)

Return the final value type produced by a parser.

This is useful when you want to refer to a parser's output type in user code,
for example to define method specializations on the result of a specific parser.

# Examples
```jldoctest
julia> using OptParse

julia> greet = command("greet", object((
           cmd = @constant(:greet),
           name = option("-n", str("NAME")),
       )));

julia> const Greet = resulttype(greet);

julia> Greet
@NamedTuple{cmd::Val{:greet}, name::String}
```

A common pattern is to define a stable alias once and dispatch on it later

# See Also
- [`argparse`](@ref)
- [`tryargparse`](@ref)
"""
resulttype(::Type{<:AbstractParser{T}}) where {T} = T
resulttype(::AbstractParser{T}) where {T} = T

include("valueparsers/valueparsers.jl")
include("primitives/primitives.jl")
include("constructors/constructors.jl")
include("modifiers/modifiers.jl")

@wrapped struct Parser{T, S, p, P} <: AbstractParser{T, S, p, P}
    union::Union{
        ArgGate{T, S, p, P},
        ArgOption{T, S, p, P},
        ArgConstant{T, S, p, P},
        ArgArgument{T, S, p, P},
        ArgCommand{T, S, p, P},

        ConstrObject{T, S, p, P},
        ConstrOr{T, S, p, P},
        ConstrTuple{T, S, p, P},

        ModWithDefault{T, S, p, P},
        ModMultiple{T, S, p, P},
    }
end

_parser(x::AbstractParser{T, S, p, P}) where {T, S, p, P} = Parser{T, S, p, P}(x)

Base.getproperty(p::Parser, f::Symbol) = @unionsplit Base.getproperty(p, f)
Base.hasproperty(p::Parser, f::Symbol) = @unionsplit Base.hasproperty(p, f)

function complete(p::Parser{T, S}, st::S)::ParseResult{T} where {T, S}
    return complete(unwrapunion(p), st)
end


# modifiers

## Default

"""
    default(p::Parser, value)
    default(value)

Modifier that provides a default value for a parser when it fails to match or is not present
in the command-line arguments.

# Arguments
- `p::Parser`: The parser to apply the default value to
- `value`: The default value to return if parsing fails (can be any type)

# Returns
A modified parser that returns `value` if the original parser fails to match.

# Examples
```jldoctest
julia> using OptParse

julia> # Parser with explicit default
       p = default(option("-p", "--port", integer()), 8080);

julia> result = argparse(p, String[]);

julia> result
8080

julia> result = argparse(p, ["--port", "3000"]);

julia> result
3000

julia> # Curried version for pipeline composition
       p = option("-p", "--port", integer()) |> default(8080);

julia> result = argparse(p, String[]);

julia> result
8080
```

# See Also
- [`optional`](@ref): Convenience wrapper using `nothing` as default
"""
function default end

default(p::Parser, value) = _parser(ModWithDefault(p, value))
default(value) = (p::Parser) -> default(p, value)

## Optional

"""
    optional(p::Parser)

Modifier that makes a parser optional, returning `nothing` if the parser fails to match.

Transforms a parser returning type `T` into a parser returning `Union{Nothing, T}`.
This is equivalent to `default(p, nothing)` and is mainly provided as a convenience wrapper.

# Arguments
- `p::Parser`: The parser to make optional

# Returns
A modified parser that returns `nothing` if parsing fails, or the parsed value otherwise.

# Examples
```jldoctest
julia> using OptParse

julia> # Optional option - returns parsed value or nothing
       port = optional(option("-p", "--port", integer()));

julia> result = argparse(port, String[]);

julia> result === nothing
true

julia> result = argparse(port, ["-p", "8080"]);

julia> result
8080
```

# See Also
- [`default`](@ref): More general modifier with custom defaults
"""
function optional end

optional(p::Parser) = default(p, nothing)
optional() = default(nothing)

## Multiple

"""
    multiple(p::Parser; kw...)

Modifier that allows a parser to match multiple times, collecting results in a vector.

Useful for parsers that should accept repeated values, such as multiple arguments,
repeated flags for verbosity levels, or collecting multiple options.

# Arguments
- `p::Parser`: The parser to apply multiple matching to

# Keywords
Additional keyword arguments are passed to tweak the behaviour
- `min::Int`: The minimum amount of times this parser must match
- `max::Int`: The maximum amount of times this parser can match

# Returns
A parser that returns a vector of values, where each value is a successful match of the
original parser.

# Examples
```jldoctest
julia> using OptParse

julia> # Multiple arguments (e.g., `add pkg1 pkg2 pkg3`)
       packages = multiple(arg(str("PACKAGE")));

julia> result = argparse(packages, ["pkg1", "pkg2", "pkg3"]);

julia> result
3-element Vector{String}:
 "pkg1"
 "pkg2"
 "pkg3"

julia> # Multiple gates for verbosity levels (e.g., `-v -v -v`)
       verbosity = multiple(gate("-v"));

julia> result = argparse(verbosity, ["-v", "-v", "-v"]);

julia> length(result)
3

julia> # Multiple options
       includes = multiple(option("-I", str()));

julia> result = argparse(includes, ["-I", "/usr/include", "-I", "/opt/include"]);

julia> result
2-element Vector{String}:
 "/usr/include"
 "/opt/include"
```

# Notes
- Returns an empty vector if no matches are found (unless combined with other modifiers)
- The order of matches is preserved
- Can be combined with other modifiers like `default`
"""
function multiple end

multiple(p::Parser; kw...) = _parser(ModMultiple(p; kw...))
multiple(; kw...) = (p::Parser) -> multiple(p; kw...)


# primitives

## Option

"""
    option(names..., valparser::ValueParser{T}; kw...) where {T}

Primitive parser that matches command-line options with associated values.

Options can be specified in multiple formats:
- Long form: `--option value` or `--option=value`
- Short form: `-o value`

# Arguments
- `names`: One or more option names (strings). Typically includes short (`"-o"`) and/or
  long (`"--option"`) forms. Can be provided as individual arguments or as a tuple.
- `valparser::ValueParser{T}`: Value parser that determines how to parse the option's value

# Keywords
- `help::String`: Stored help text metadata for this option

# Returns
A parser that matches the specified option patterns and returns a value of type `T`.

# Examples
```jldoctest
julia> using OptParse

julia> # Single long option
       port = option("--port", integer());

julia> result = argparse(port, ["--port", "8080"]);

julia> result
8080

julia> # Short and long forms
       port = option("-p", "--port", integer());

julia> result = argparse(port, ["-p", "3000"]);

julia> result
3000

julia> result = argparse(port, ["--port", "3000"]);

julia> result
3000

julia> # With equals sign
       result = argparse(port, ["--port=3000"]);

julia> result
3000

julia> # With constraints
       level = option("-l", "--level", choice(["debug", "info", "warn"]));

julia> result = argparse(level, ["-l", "debug"]);

julia> result
"DEBUG"

julia> @enum Mode begin
           Debug
           Release
       end

julia> mode = option("--mode", choice(Mode));

julia> argparse(mode, ["--mode", "release"])
Release::Mode = 1
```

# Notes
- The first matching pattern is used
- `=` attachment is supported for long options only
- Option names should include their prefix (`-` or `--`)
"""
function option end

option(names::Tuple{Vararg{String}}, valparser::ValueParser{T}; kw...) where {T} =
    _parser(ArgOption(names, valparser; kw...))
option(opt1::String, valparser::ValueParser{T}; kw...) where {T} =
    _parser(ArgOption((opt1,), valparser; kw...))
option(opt1::String, opt2::String, valparser::ValueParser{T}; kw...) where {T} =
    _parser(ArgOption((opt1, opt2), valparser; kw...))
option(opt1::String, opt2::String, opt3::String, valparser::ValueParser{T}; kw...) where {T} =
    _parser(ArgOption((opt1, opt2, opt3), valparser; kw...))

option(names::Tuple{Vararg{String}}; kw...) = (valp::ValueParser) -> option(names, valp; kw...)

## Gate

"""
    gate(names...; kw...)

Primitive parser that requires a boolean flag to be present.

Gates represent required flag markers used to activate features or guard specific
subtrees. When present in arguments, they indicate `true`; when absent, parsing fails
(unless wrapped with modifiers like `optional` or `default`).

# Arguments
- `names...`: One or more flag names (strings). Can include short (`"-v"`) and/or
  long (`"--verbose"`) forms

# Keywords
- `help::String`: Stored help text metadata for this flag

# Returns
A parser that returns `true` when the flag is present.

# Examples
```jldoctest
julia> using OptParse

julia> # Simple gate
       experimental = gate("--experimental");

julia> result = argparse(experimental, ["--experimental"]);

julia> result
true

julia> # Multiple names
       debug = gate("-d", "--debug");

julia> result = argparse(debug, ["-d"]);

julia> result
true

julia> result = argparse(debug, ["--debug"]);

julia> result
true

```

# Notes
- By itself, `gate` requires the flag to be present (fails if absent)
- Use `flag` for optional boolean flags that default to `false`
- Supports bundled short options (e.g., `-abc` equivalent to `-a -b -c`)

# See Also
- [`flag`](@ref): Optional flag that defaults to `false`
"""
function gate end

gate(names...; kw...) = _parser(ArgGate(names; kw...))

## Flag

"""
    flag(names...; kw...)

Convenience function for an optional flag that defaults to `false`.

This is equivalent to `default(gate(names...; kw...), false)`. When the flag is
present in arguments, it returns `true`; when absent, it returns `false`.

# Arguments
- `names...`: One or more flag names (strings)

# Keywords
- `help::String`: Stored help text metadata for this flag

# Returns
A parser that returns `true` if the flag is present, `false` otherwise.

# Examples
```jldoctest
julia> using OptParse

julia> # Basic usage
       verbose = flag("-v", "--verbose");

julia> result = argparse(verbose, String[]);

julia> result
false

julia> result = argparse(verbose, ["-v"]);

julia> result
true

julia> # In an object parser
       parser = object((
           help = flag("-h", "--help"),
           version = flag("--version"),
           quiet = flag("-q", "--quiet")
       ));

julia> result = argparse(parser, ["-h", "--version"]);

julia> (result.help, result.version, result.quiet)
(true, true, false)

julia> verbosity = multiple(gate("-v")); # Multiple verbosity levels using multiple

julia> result = argparse(verbosity, ["-v", "-v", "-v"]);

julia> result
3-element Vector{Bool}:
 1
 1
 1
```

# Implementation Note
This is implemented as: `default(gate(names...; kw...), false)`

# See Also
- [`gate`](@ref): Required flag that fails if absent
- [`default`](@ref): General modifier for default values
"""
function flag end

flag(names...; kw...) = default(gate(names...; kw...), false)

## Constant

"""
    @constant(val)

Macro that creates a parser which always returns the specified constant value.

This is useful for tagging different branches in an `or` combinator or for providing
fixed values in your parsed result structure.

# Arguments
- `val`: The constant value to return (can be any type)

# Returns
A parser that always succeeds and returns `val` without consuming any input.

# Examples
```jldoctest
julia> using OptParse

julia> # Tagging subcommands
       addCmd = command("add", object((
           action = @constant(:add),
           key = arg(str("KEY")),
           value = arg(str("VALUE"))
       )));

julia> removeCmd = command("remove", object((
           action = @constant(:remove),
           key = arg(str("KEY"))
       )));

julia> parser = or(addCmd, removeCmd);

julia> result = argparse(parser, ["add", "username", "alice"]);

julia> result.action
Val{:add}()

julia> result.key
"username"

julia> result.value
"alice"

julia> # Providing metadata
       parser2 = object((
           version = @constant(Symbol("1.0.0")),
           name = arg(str())
       ));

julia> result = argparse(parser2, ["myapp"]);

julia> result.version
Val{Symbol("1.0.0")}()

julia> result.name
"myapp"
```

# Notes
- Does not consume any command-line tokens
- Always succeeds (never fails to parse)
- Useful for discriminating between branches in an `or` combinator
"""
macro constant(val)
    return :(_parser(ArgConstant($val)))
end

## Arg

"""
    arg(valparser::ValueParser{T}; kw...) where {T}

Primitive parser for positional arguments not associated with a flag or option.

Arguments are parsed based on their position in the command line and must appear
in the order they're defined (though they can be interspersed with options).

# Arguments
- `valparser::ValueParser{T}`: Value parser that determines how to parse the argument's value

# Keywords
- `help::String`: Stored help text metadata for this argument

# Returns
A parser that matches a positional argument and returns a value of type `T`.

# Examples
```jldoctest
julia> using OptParse

julia> # Single argument
       source = arg(str("SOURCE"));

julia> result = argparse(source, ["/path/to/file"]);

julia> result
"/path/to/file"

julia> # Multiple positional arguments
       parser = object((
           source = arg(str("SOURCE")),
           dest = arg(str("DEST"))
       ));

julia> result = argparse(parser, ["/from/here", "/to/here"]);

julia> result.source
"/from/here"

julia> result.dest
"/to/here"

julia> # Variable number of arguments
       files = multiple(arg(str("FILE")));

julia> result = argparse(files, ["file1.txt", "file2.txt", "file3.txt"]);

julia> result
3-element Vector{String}:
 "file1.txt"
 "file2.txt"
 "file3.txt"

julia> # Arguments with type constraints
       port = arg(integer(min=1000, max=65535));

julia> result = argparse(port, ["8080"]);

julia> result
8080

julia> # Mixed with options (order flexible)
       parser = object((
           input = arg(str("INPUT")),
           output = option("-o", "--output", str()),
           verbose = flag("-v")
       ));

julia> result = argparse(parser, ["input.txt", "-o", "output.txt", "-v"]);

julia> result.input
"input.txt"

julia> result = argparse(parser, ["-v", "input.txt", "-o", "output.txt"]);

julia> result.input
"input.txt"
```

# Notes
- Arguments must be present unless wrapped with `optional` or `default`
- The `metavar` in the value parser is used in diagnostics and usage/help metadata
- Arguments are parsed in order but can be interspersed with options
- After `--`, remaining tokens are treated as positional input
"""
function arg end

arg(valparser::ValueParser{T}; kw...) where {T} = _parser(ArgArgument(valparser; kw...))
arg(; kw...) = (valp::ValueParser) -> arg(valp; kw...)

## command

"""
    command(name::String, p::Parser; kw...)
    command(name::String, alias::String, p::Parser; kw...)

Primitive parser that matches a subcommand and its associated arguments.

Commands are a hybrid between an option and a constructor - they match a specific
keyword and then delegate to another parser for the remaining arguments. This is
the primary way to implement subcommands in CLI applications.

# Arguments
- `name::String`: The command name to match
- `p::Parser`: The parser to use for arguments following the command

# Keywords
- `help::String`: Stored help text metadata for this command
- `brief::String`: Stored short help metadata for this command
- `footer::String`: Stored footer metadata for this command

# Returns
A parser that matches the command name and then parses the remaining arguments
using the provided parser.

# Examples
```jldoctest
julia> using OptParse

julia> # Simple command
       instantiate = command("instantiate", object((
           verbose = flag("-v", "--verbose"),
           manifest = flag("-m", "--manifest")
       )));

julia> result = argparse(instantiate, ["instantiate", "-v", "-m"]);

julia> (result.verbose, result.manifest)
(true, true)

julia> # Multiple commands with or combinator
       addCmd = command("add", object((
           action = @constant(:add),
           packages = multiple(arg(str("PACKAGE")))
       )));

julia> removeCmd = command("remove", object((
           action = @constant(:remove),
           packages = multiple(arg(str("PACKAGE")))
       )));

julia> pkgParser = or(addCmd, removeCmd);

julia> result = argparse(pkgParser, ["add", "OptParse", "DataFrames"]);

julia> result.action
Val{:add}()

julia> result.packages
2-element Vector{String}:
 "OptParse"
 "DataFrames"

julia> result = argparse(pkgParser, ["remove", "OldPkg"]);

julia> result.action
Val{:remove}()

julia> result.packages
1-element Vector{String}:
 "OldPkg"
```

# Notes
- Command name must match exactly (case-sensitive)
- Commands consume their name token from the input
- Often combined with `or` to provide multiple subcommands
- Can be nested to create hierarchical command structures
"""
function command end

command(names::Tuple{Vararg{String}}, p::Parser; kw...) = _parser(ArgCommand(names, p; kw...))
command(name::String, p::Parser; kw...) = _parser(ArgCommand((name,), p; kw...))
command(name::String, alias::String, p::Parser; kw...) = _parser(ArgCommand((name, alias), p; kw...))


# constructors

## Object

"""
    object(obj::NamedTuple)
    object(objlabel, obj::NamedTuple)

Constructor that creates a parser from a named tuple of parsers, returning a named tuple
of parsed values.

This is the primary way to combine multiple parsers into a cohesive structure. Each field
in the named tuple should be a parser, and the result will be a named tuple with the same
field names containing the parsed values.

# Arguments
- `obj::NamedTuple`: Named tuple where each field is a parser
- `objlabel`: Optional label used in diagnostics and stored as object metadata

# Returns
A parser that returns a named tuple with the same structure as `obj`, where each field
contains the parsed result from the corresponding parser.

# Examples
```jldoctest
julia> using OptParse

julia> # Basic usage
       parser = object((
           name = option("-n", "--name", str()),
           port = option("-p", "--port", integer()),
           verbose = flag("-v")
       ));

julia> result = argparse(parser, ["-n", "server", "-p", "8080", "-v"]);

julia> result.name
"server"

julia> result.port
8080

julia> result.verbose
true

julia> parser = object("config", (
           host = option("--host", str()),
           port = option("--port", integer())
       )); # With a label for clearer diagnostics

julia> result = argparse(parser, ["--host", "localhost", "--port", "3000"]);

julia> result.host
"localhost"

julia> parser = object((
           server = object((
               host = option("--host", str()),
               port = option("--port", integer())
           )),
           timeout = option("--timeout", integer())
       ));  # Nested objects

julia> result = argparse(parser, ["--host", "localhost", "--port", "8080", "--timeout", "30"]);

julia> result.server.host
"localhost"

julia> result.server.port
8080

julia> result.timeout
30
```

# Notes
- Parsers can appear in any order in the command line (unless they're positional arguments)
- All parsers must succeed unless they're optional or have defaults
- Type-stable: the return type is fully determined at compile time
- Field names become the keys in the result

# See Also
- [`combine`](@ref): Combine multiple objects into one
- [`sequence`](@ref): Ordered tuple constructor
"""
function object end

object(obj::NamedTuple) = _parser(ConstrObject(obj))
object(objlabel, obj::NamedTuple) = _parser(ConstrObject(obj; label = objlabel))

## Combine

"""
    combine(objs...)
    combine(label::String, objs...)

Constructor that combines multiple object parsers into a single parser.

This is useful for composing parsers from reusable components or for organizing
large parser definitions into logical groups.

# Arguments
- `label::String = ""`: Optional label used in diagnostics and stored as object metadata
- `objs...`: Multiple object parsers to merge


# Returns
A parser that combines all fields from the input objects into a single result.

# Examples
```jldoctest
julia> using OptParse

julia> # Reusable parser components
       commonOpts = object((
           verbose = flag("-v", "--verbose"),
           quiet = flag("-q", "--quiet")
       ));

julia> networkOpts = object((
           host = option("--host", str()),
           port = option("--port", integer())
       ));

julia> # Merge into single parser
       parser = combine(commonOpts, networkOpts);

julia> result = argparse(parser, ["-v", "--host", "localhost", "--port", "8080"]);

julia> result.verbose
true

julia> result.host
"localhost"

julia> result.port
8080

julia> # With label
       parser = combine("server_options", commonOpts, networkOpts);

julia> result = argparse(parser, ["--host", "127.0.0.1", "--port", "3000", "-v"]);

julia> result.host
"127.0.0.1"
```

# Notes
- Field names must be unique across all merged objects
- Duplicate field names will cause an error
- Maintains type stability
- Useful for DRY (Don't Repeat Yourself) principle in parser definitions

# See Also
- [`object`](@ref): Create parser from single named tuple
- [`concat`](@ref): Similar operation for sequence constructors
"""
function combine end


combine(objs...) = _parser(ConstrObject(_merge(objs)))
combine(label::String, objs...) = _parser(ConstrObject(_merge(objs); label))

## Or

"""
    or(parsers...)

Combinator that creates a parser matching exactly one of the provided parsers.

The `or` combinator tries each parser in sequence and succeeds with the first one
that matches. All parsers are mutually exclusive - only one can succeed. This is
the primary way to implement subcommands or alternative parsing branches.

`or(...)` is order-dependent: branches are tried in the order they are listed,
and the first semantic match wins. Put broader positional parsers like
`arg(...)` or `multiple(arg(...))` last.

# Arguments
- `parsers...`: Variable number of parsers to try in order

# Returns
A parser that returns the result of the first successfully matching parser.

# Examples
```jldoctest
julia> using OptParse

julia> # Subcommands
       addCmd = command("add", object((
           action = @constant(:add),
           packages = multiple(arg(str("PACKAGE")))
       )));

julia> removeCmd = command("remove", object((
           action = @constant(:remove),
           packages = multiple(arg(str("PACKAGE")))
       )));

julia> parser = or(addCmd, removeCmd);

julia> result = argparse(parser, ["add", "Package1", "Package2"]);

julia> result.action
Val{:add}()

julia> result.packages
2-element Vector{String}:
 "Package1"
 "Package2"

julia> result = argparse(parser, ["remove", "OldPackage"]);

julia> result.action
Val{:remove}()

julia> # Alternative formats
       helpFormat = or(
           gate("-h"),
           gate("--help"),
           gate("-?")
       );

julia> result = argparse(helpFormat, ["-h"]);

julia> result
true

julia> result = argparse(helpFormat, ["--help"]);

julia> result
true

julia> # Different configuration modes
       config = or(
           object((mode = @constant(:file), file = option("-f", str()))),
           object((mode = @constant(:inline), config = option("-c", str())))
       );

julia> result = argparse(config, ["-f", "config.toml"]);

julia> result.mode
Val{:file}()

julia> result.file
"config.toml"
```

# Notes
- Parsers are tried in order; first semantic match wins
- If no parser matches, the overall parse fails
- Use with `@constant` to tag which branch was taken
- Type of result is `Union` of all parser return types (type-stable)
- All alternatives should typically be mutually exclusive for clarity

# See Also
- [`command`](@ref): Often used with `or` for subcommands
- `@constant`: Useful for tagging branches
"""
function or end

or(parsers...) = _parser(ConstrOr(parsers))

## Sequence

"""
    sequence(parsers...; kw...)
    sequence(label::String, parsers...; kw...)

Constructor that creates an ordered sequence parser from multiple parsers.

Similar to `object` but maintains argument order and returns a tuple instead of
a named tuple. The order of results matches the order of parsers, even if command-line
arguments appear in a different order.

# Arguments
- `label::String`: Optional label used in diagnostics and stored as tuple metadata
- `parsers...`: Variable number of parsers in desired result order

# Returns
A parser that returns a tuple of parsed values in the same order as the parsers.

# Examples
```jldoctest
julia> using OptParse

julia> # Basic tuple
       parser = sequence(
           option("-x", integer()),
           option("-y", integer())
       );

julia> result = argparse(parser, ["-y", "20", "-x", "10"]);

julia> result
(10, 20)

julia> # With label
       parser = sequence("coordinates",
           option("-x", integer()),
           option("-y", integer()),
           option("-z", integer())
       );

julia> result = argparse(parser, ["-z", "30", "-x", "10", "-y", "20"]);

julia> result
(10, 20, 30)

julia> # Mixed with arguments
       parser = sequence(
           arg(str("INPUT")),
           option("-o", str()),
           gate("-v")
       );

julia> result = argparse(parser, ["input.txt", "-v", "-o", "output.txt"]);

julia> result
("input.txt", "output.txt", true)

```

# Notes
- Return order is determined by parser definition order, not argument order
- More restrictive than `object` - cannot access results by name
- Useful when you need guaranteed ordering
- Can be nested for complex structures

# See Also
- [`object`](@ref): Named tuple constructor (more flexible)
- [`concat`](@ref): Concatenate multiple sequences
"""
function sequence end

sequence(parsers...; kw...) = _parser(ConstrTuple(parsers; kw...))
sequence(parsers::Tuple{Vararg{Parser}}; kw...) = _parser(ConstrTuple(parsers; kw...))
sequence(label::String, parsers...; kw...) = _parser(ConstrTuple(parsers; label, kw...))
sequence(label::String, parsers::Tuple{Vararg{Parser}}; kw...) = _parser(ConstrTuple(parsers; label, kw...))

## Concat

"""
    concat(seqs...; label = "")

Constructor that concatenates multiple sequence parsers into a single flat tuple.

This is useful for composing parsers from reusable sequence components while maintaining
a single flat result structure.

# Arguments
- `seqs...`: Multiple sequence parsers to concatenate

# Keywords
- `label::String = ""`: Optional label used in diagnostics and stored as tuple metadata

# Returns
A parser that combines all elements from the input tuples into a single flat tuple.

# Examples
```jldoctest
julia> using OptParse

julia> # Reusable sequence components
       positionArgs = sequence(
           option("-x", integer()),
           option("-y", integer())
       );

julia> sizeArgs = sequence(
           option("--width", integer()),
           option("--height", integer())
       );

julia> # Concatenate into single tuple
       parser = concat(positionArgs, sizeArgs);

julia> result = argparse(parser, ["-x", "10", "-y", "20", "--width", "100", "--height", "50"]);

julia> result
(10, 20, 100, 50)

julia> # With label
       parser = concat(
           sequence(option("--host", str())),
           sequence(option("--port", integer())),
           label = "connection"
       );

julia> result = argparse(parser, ["--host", "localhost", "--port", "8080"]);

julia> result
("localhost", 8080)

julia> # Multiple concatenations
       headerArgs = sequence(option("-H", str()));

julia> bodyArgs = sequence(option("-d", str()));

julia> authArgs = sequence(option("-u", str()), option("-p", str()));

julia> httpParser = concat(headerArgs, bodyArgs, authArgs, label = "http_request");

julia> result = argparse(httpParser, ["-H", "Content-Type: json", "-d", "data", "-u", "user", "-p", "pass"]);

julia> result
("Content-Type: json", "data", "user", "pass")
```

# Notes
- Results in a flat tuple, not nested tuples
- Maintains order across all concatenated sequences
- Useful for DRY principle with sequence-based parsers

# See Also
- [`sequence`](@ref): Create individual sequences
- [`combine`](@ref): Similar operation for object constructors
"""
function concat end

concat(seqs...; label = "") = _parser(ConstrTuple(_concat(seqs); label))
