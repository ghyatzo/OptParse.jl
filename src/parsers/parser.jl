abstract type AbstractParser{T, S, p, P} end

tval(::Type{<:AbstractParser{T}}) where {T} = T
tval(::AbstractParser{T}) where {T} = T

tstate(::Type{<:AbstractParser{T, S}}) where {T, S} = S
tstate(::AbstractParser{T, S}) where {T, S} = S

(priority(::Type{<:AbstractParser{T, S, _p}})::Int) where {T, S, _p} = _p
(priority(::AbstractParser{T, S, _p})::Int) where {T, S, _p} = _p

ptypes(::Type{<:AbstractParser{T, S, _p, P}}) where {T, S, _p, P} = P
ptypes(::AbstractParser{T, S, _p, P}) where {T, S, _p, P} = P


struct Context{S}
    buffer::Vector{String}
    state::S # accumulator for partial states (eg named tuple, single result, etc)
    optionsTerminated::Bool
end

Context(args::Vector{String}, state) =
    Context{typeof(state)}(args, state, false)


struct ParseSuccess{S}
    consumed::Tuple{Vararg{String}}
    next::Context{S}
end

ParseSuccess(cons::Vector{String}, next::Context{S}) where {S} = ParseSuccess{S}((cons...,), next)
ParseSuccess(cons::String, next::Context{S}) where {S} = ParseSuccess{S}((cons,), next)

struct ParseFailure{E}
    consumed::Int
    error::E
end

const ParseResult{S, E} = Result{ParseSuccess{S}, ParseFailure{E}}

ParseOk(consumed, next::Context{S}) where {S} = Ok(ParseSuccess(consumed, next))
ParseErr(consumed, error) = Err(ParseFailure(consumed, error))


include("valueparsers/valueparsers.jl")
include("primitives/primitives.jl")
include("constructors/constructors.jl")
include("modifiers/modifiers.jl")

@wrapped struct Parser{T, S, p, P} <: AbstractParser{T, S, p, P}
    union::Union{
        ArgFlag{T, S, p, P},
        ArgOption{T, S, p, P},
        ArgConstant{T, S, p, P},
        ArgArgument{T, S, p, P},
        ArgCommand{T, S, p, P},

        ConstrObject{T, S, p, P},
        ConstrOr{T, S, p, P},
        ConstrTuple{T, S, p, P},

        ModOptional{T, S, p, P},
        ModWithDefault{T, S, p, P},
        ModMultiple{T, S, p, P},
    }
end

_parser(x::ArgFlag{T, S, p, P}) where {T, S, p, P} = Parser{T, S, p, P}(x)
_parser(x::ArgOption{T, S, p, P}) where {T, S, p, P} = Parser{T, S, p, P}(x)
_parser(x::ArgConstant{T, S, p, P}) where {T, S, p, P} = Parser{T, S, p, P}(x)
_parser(x::ArgArgument{T, S, p, P}) where {T, S, p, P} = Parser{T, S, p, P}(x)
_parser(x::ArgCommand{T, S, p, P}) where {T, S, p, P} = Parser{T, S, p, P}(x)

_parser(x::ConstrObject{T, S, p, P}) where {T, S, p, P} = Parser{T, S, p, P}(x)
_parser(x::ConstrOr{T, S, p, P}) where {T, S, p, P} = Parser{T, S, p, P}(x)
_parser(x::ConstrTuple{T, S, p, P}) where {T, S, p, P} = Parser{T, S, p, P}(x)

_parser(x::ModOptional{T, S, p, P}) where {T, S, p, P} = Parser{T, S, p, P}(x)
_parser(x::ModWithDefault{T, S, p, P}) where {T, S, p, P} = Parser{T, S, p, P}(x)
_parser(x::ModMultiple{T, S, p, P}) where {T, S, p, P} = Parser{T, S, p, P}(x)

Base.getproperty(p::Parser, f::Symbol) = @unionsplit Base.getproperty(p, f)
Base.hasproperty(p::Parser, f::Symbol) = @unionsplit Base.hasproperty(p, f)

# modifiers

## WithDefault

"""
    withDefault(p::Parser, default)
    withDefault(default)

Modifier that provides a default value for a parser when it fails to match or is not present
in the command-line arguments.

# Arguments
- `p::Parser`: The parser to apply the default value to
- `default`: The default value to return if parsing fails (can be any type)

# Returns
A modified parser that returns `default` if the original parser fails to match.

# Examples
```jldoctest
julia> using OptParse

julia> # Parser with explicit default
       p = withDefault(option("-p", "--port", integer()), 8080);

julia> result = argparse(p, String[]);

julia> result
8080

julia> result = argparse(p, ["--port", "3000"]);

julia> result
3000

julia> # Curried version for pipeline composition
       p = option("-p", "--port", integer()) |> withDefault(8080);

julia> result = argparse(p, String[]);

julia> result
8080
```

# See Also
- [`optional`](@ref): Convenience wrapper using `nothing` as default
"""
function withDefault end

withDefault(p::Parser, default) = _parser(ModWithDefault(p, default))
withDefault(default) = (p::Parser) -> withDefault(p, default)

## Optional

"""
    optional(p::Parser)

Modifier that makes a parser optional, returning `nothing` if the parser fails to match.

Transforms a parser returning type `T` into a parser returning `Union{Nothing, T}`.
This is equivalent to `withDefault(p, nothing)`.

# Arguments
- `p::Parser`: The parser to make optional

# Returns
A modified parser that returns `nothing` if parsing fails, or the parsed value otherwise.

# Examples
```jldoctest
julia> using OptParse

julia> # Optional flag - returns true if present, nothing otherwise
       verbose = optional(flag("-v", "--verbose"));

julia> result = argparse(verbose, String[]);

julia> result === nothing
true

julia> result = argparse(verbose, ["-v"]);

julia> result
true

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
- [`withDefault`](@ref): More general modifier with custom defaults
"""
function optional end

optional(p::Parser) = withDefault(p, nothing)
optional() = withDefault(nothing)

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
       packages = multiple(argument(str(metavar="PACKAGE")));

julia> result = argparse(packages, ["pkg1", "pkg2", "pkg3"]);

julia> result
3-element Vector{String}:
 "pkg1"
 "pkg2"
 "pkg3"

julia> # Multiple flags for verbosity levels (e.g., `-v -v -v`)
       verbosity = multiple(flag("-v"));

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
- Can be combined with other modifiers like `withDefault`
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
- Windows style: `/O value` or `/O:value`

# Arguments
- `names`: One or more option names (strings). Typically includes short (`"-o"`) and/or
  long (`"--option"`) forms. Can be provided as individual arguments or as a tuple.
- `valparser::ValueParser{T}`: Value parser that determines how to parse the option's value

# Keywords
- `desc::String`: Help text description for this option (used in help messages)

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
       level = option("-l", "--level", choice("debug", "info", "warn"));

julia> result = argparse(level, ["-l", "debug"]);

julia> result
"debug"
```

# Notes
- The first matching pattern is used
- Values can be attached with `=` (long form) or directly (short form)
- Option names should include their prefix (`-`, `--`, or `/`)
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

## Flag

"""
    flag(names...; kw...)

Primitive parser that matches boolean flags without associated values.

Flags represent on/off states and are used to activate features or modify behavior.
When present in arguments, they indicate `true`; when absent, parsing fails (unless
wrapped with modifiers like `optional` or `withDefault`).

# Arguments
- `names...`: One or more flag names (strings). Can include short (`"-v"`) and/or
  long (`"--verbose"`) forms

# Keywords
- `desc::String`: Help text description for this option (used in help messages)

# Returns
A parser that returns `true` when the flag is present.

# Examples
```jldoctest
julia> using OptParse

julia> # Simple flag
       verbose = flag("--verbose");

julia> result = argparse(verbose, ["--verbose"]);

julia> result
true

julia> # Multiple names
       debug = flag("-d", "--debug");

julia> result = argparse(debug, ["-d"]);

julia> result
true

julia> result = argparse(debug, ["--debug"]);

julia> result
true

julia> # Bundled short flags: `-abc` parsed as `-a -b -c`
       flags = object((
           all = flag("-a"),
           brief = flag("-b"),
           color = flag("-c")
       ));

julia> result = argparse(flags, ["-abc"]);

julia> (result.all, result.brief, result.color)
(true, true, true)
```

# Notes
- By itself, `flag` requires the flag to be present (fails if absent)
- Use `switch` for optional flags that default to `false`
- Supports bundled short options (e.g., `-abc` equivalent to `-a -b -c`)

# See Also
- [`switch`](@ref): Optional flag that defaults to `false`
"""
function flag end

flag(names...; kw...) = _parser(ArgFlag(names; kw...))

## switch

"""
    switch(names...; kw...)

Convenience function for an optional flag that defaults to `false`.

This is equivalent to `withDefault(flag(names...; kw...), false)`. When the flag is
present in arguments, it returns `true`; when absent, it returns `false`.

# Arguments
- `names...`: One or more flag names (strings)

# Keywords
- `desc::String`: Help text description for this option (used in help messages)

# Returns
A parser that returns `true` if the flag is present, `false` otherwise.

# Examples
```jldoctest
julia> using OptParse

julia> # Basic usage
       verbose = switch("-v", "--verbose");

julia> result = argparse(verbose, String[]);

julia> result
false

julia> result = argparse(verbose, ["-v"]);

julia> result
true

julia> # In an object parser
       parser = object((
           help = switch("-h", "--help"),
           version = switch("--version"),
           quiet = switch("-q", "--quiet")
       ));

julia> result = argparse(parser, ["-h", "--version"]);

julia> (result.help, result.version, result.quiet)
(true, true, false)

julia> # Multiple verbosity levels using multiple
       verbosity = multiple(switch("-v"));

julia> result = argparse(verbosity, ["-v", "-v", "-v"]);

julia> result
3-element Vector{Bool}:
 true
 true
 true
```

# Implementation Note
This is implemented as: `withDefault(flag(names...; kw...), false)`

# See Also
- [`flag`](@ref): Required flag that fails if absent
- [`withDefault`](@ref): General modifier for default values
"""
function switch end

switch(names...; kw...) = withDefault(flag(names...; kw...), false)

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
           key = argument(str(metavar="KEY")),
           value = argument(str(metavar="VALUE"))
       )));

julia> removeCmd = command("remove", object((
           action = @constant(:remove),
           key = argument(str(metavar="KEY"))
       )));

julia> parser = or(addCmd, removeCmd);

julia> result = argparse(parser, ["add", "username", "alice"]);

julia> result.action
:add

julia> result.key
"username"

julia> result.value
"alice"

julia> # Providing metadata
       parser = object((
           version = @constant("1.0.0"),
           name = argument(str())
       ));

julia> result = argparse(parser, ["myapp"]);

julia> result.version
"1.0.0"

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

## Argument

"""
    argument(valparser::ValueParser{T}; kw...) where {T}

Primitive parser for positional arguments not associated with a flag or option.

Arguments are parsed based on their position in the command line and must appear
in the order they're defined (though they can be interspersed with options).

# Arguments
- `valparser::ValueParser{T}`: Value parser that determines how to parse the argument's value

# Keywords
- `desc::String`: Help text description for this option (used in help messages)

# Returns
A parser that matches a positional argument and returns a value of type `T`.

# Examples
```jldoctest
julia> using OptParse

julia> # Single argument
       source = argument(str(metavar="SOURCE"));

julia> result = argparse(source, ["/path/to/file"]);

julia> result
"/path/to/file"

julia> # Multiple positional arguments
       parser = object((
           source = argument(str(metavar="SOURCE")),
           dest = argument(str(metavar="DEST"))
       ));

julia> result = argparse(parser, ["/from/here", "/to/here"]);

julia> result.source
"/from/here"

julia> result.dest
"/to/here"

julia> # Variable number of arguments
       files = multiple(argument(str(metavar="FILE")));

julia> result = argparse(files, ["file1.txt", "file2.txt", "file3.txt"]);

julia> result
3-element Vector{String}:
 "file1.txt"
 "file2.txt"
 "file3.txt"

julia> # Arguments with type constraints
       port = argument(integer(min=1000, max=65535));

julia> result = argparse(port, ["8080"]);

julia> result
8080

julia> # Mixed with options (order flexible)
       parser = object((
           input = argument(str(metavar="INPUT")),
           output = option("-o", "--output", str()),
           verbose = switch("-v")
       ));

julia> result = argparse(parser, ["input.txt", "-o", "output.txt", "-v"]);

julia> result.input
"input.txt"

julia> result = argparse(parser, ["-v", "input.txt", "-o", "output.txt"]);

julia> result.input
"input.txt"
```

# Notes
- Arguments must be present unless wrapped with `optional` or `withDefault`
- The `metavar` in the value parser is used for help text generation
- Arguments are parsed in order but can be interspersed with options
"""
function argument end

argument(valparser::ValueParser{T}; kw...) where {T} = _parser(ArgArgument(valparser; kw...))
argument(; kw...) = (valp::ValueParser) -> argument(valp; kw...)

## command

"""
    command(name::String, p::Parser; kw...)

Primitive parser that matches a subcommand and its associated arguments.

Commands are a hybrid between an option and a constructor - they match a specific
keyword and then delegate to another parser for the remaining arguments. This is
the primary way to implement subcommands in CLI applications.

# Arguments
- `name::String`: The command name to match
- `p::Parser`: The parser to use for arguments following the command

# Keywords
- `desc::String`: Help text description for this option (used in help messages)
- `brief::String`: Extra Help text
- `footer::String`: Extra help text

# Returns
A parser that matches the command name and then parses the remaining arguments
using the provided parser.

# Examples
```jldoctest
julia> using OptParse

julia> # Simple command
       instantiate = command("instantiate", object((
           verbose = switch("-v", "--verbose"),
           manifest = switch("-m", "--manifest")
       )));

julia> result = argparse(instantiate, ["instantiate", "-v", "-m"]);

julia> (result.verbose, result.manifest)
(true, true)

julia> # Multiple commands with or combinator
       addCmd = command("add", object((
           action = @constant(:add),
           packages = multiple(argument(str(metavar="PACKAGE")))
       )));

julia> removeCmd = command("remove", object((
           action = @constant(:remove),
           packages = multiple(argument(str(metavar="PACKAGE")))
       )));

julia> pkgParser = or(addCmd, removeCmd);

julia> result = argparse(pkgParser, ["add", "OptParse", "DataFrames"]);

julia> result.action
:add

julia> result.packages
2-element Vector{String}:
 "OptParse"
 "DataFrames"

julia> result = argparse(pkgParser, ["remove", "OldPkg"]);

julia> result.action
:remove

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
- `objlabel`: Optional label for the object (used in help text and error messages)

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
           verbose = switch("-v")
       ));

julia> result = argparse(parser, ["-n", "server", "-p", "8080", "-v"]);

julia> result.name
"server"

julia> result.port
8080

julia> result.verbose
true

julia> # With label for better error messages
       parser = object(:config, (
           host = option("--host", str()),
           port = option("--port", integer())
       ));

julia> result = argparse(parser, ["--host", "localhost", "--port", "3000"]);

julia> result.host
"localhost"

julia> # Nested objects
       parser = object((
           server = object((
               host = option("--host", str()),
               port = option("--port", integer())
           )),
           timeout = option("--timeout", integer())
       ));

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
- [`objmerge`](@ref): Merge multiple objects into one
- [`tup`](@ref): Ordered tuple constructor
"""
function object end

object(obj::NamedTuple) = _parser(_object(obj))
object(objlabel, obj::NamedTuple) = _parser(_object(obj; label = objlabel))

## Objmerge

"""
    objmerge(objs...)
    objmerge(label::String, objs...)

Constructor that merges multiple object parsers into a single parser.

This is useful for composing parsers from reusable components or for organizing
large parser definitions into logical groups.

# Arguments
- `label::String = ""`: Optional label for the merged object (used in help text)
- `objs...`: Multiple named tuples representing object parsers to merge


# Returns
A parser that combines all fields from the input objects into a single result.

# Examples
```jldoctest
julia> using OptParse

julia> # Reusable parser components
       commonOpts = (
           verbose = switch("-v", "--verbose"),
           quiet = switch("-q", "--quiet")
       );

julia> networkOpts = (
           host = option("--host", str()),
           port = option("--port", integer())
       );

julia> # Merge into single parser
       parser = objmerge(commonOpts, networkOpts);

julia> result = argparse(parser, ["-v", "--host", "localhost", "--port", "8080"]);

julia> result.verbose
true

julia> result.host
"localhost"

julia> result.port
8080

julia> # With label
       parser = objmerge("server_options", commonOpts, networkOpts);

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
- [`concat`](@ref): Similar operation for tuple constructors
"""
function objmerge end


objmerge(objs...) = _parser(_object(_merge(objs)))
objmerge(label::String, objs...) = _parser(_object(_merge(objs); label))

## Or

"""
    or(parsers...)

Combinator that creates a parser matching exactly one of the provided parsers.

The `or` combinator tries each parser in sequence and succeeds with the first one
that matches. All parsers are mutually exclusive - only one can succeed. This is
the primary way to implement subcommands or alternative parsing branches.

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
           packages = multiple(argument(str(metavar="PACKAGE")))
       )));

julia> removeCmd = command("remove", object((
           action = @constant(:remove),
           packages = multiple(argument(str(metavar="PACKAGE")))
       )));

julia> parser = or(addCmd, removeCmd);

julia> result = argparse(parser, ["add", "Package1", "Package2"]);

julia> result.action
:add

julia> result.packages
2-element Vector{String}:
 "Package1"
 "Package2"

julia> result = argparse(parser, ["remove", "OldPackage"]);

julia> result.action
:remove

julia> # Alternative formats
       helpFormat = or(
           flag("-h"),
           flag("--help"),
           flag("-?")
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
:file

julia> result.file
"config.toml"
```

# Notes
- Parsers are tried in order; first match wins
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

## Tup

"""
    tup(parsers...; kw...)
    tup(label::String, parsers...; kw...)

Constructor that creates an ordered tuple parser from multiple parsers.

Similar to `object` but maintains argument order and returns a tuple instead of
a named tuple. The order of results matches the order of parsers, even if command-line
arguments appear in a different order.

# Arguments
- `label::String`: Optional label for the tuple (used in help text)
- `parsers...`: Variable number of parsers in desired result order

# Keywords
- `allowDuplicates::Bool = false`: Whether to allow duplicate parsers in the tuple
- Additional keyword arguments are passed to the underlying `ConstrTuple` constructor

# Returns
A parser that returns a tuple of parsed values in the same order as the parsers.

# Examples
```jldoctest
julia> using OptParse

julia> # Basic tuple
       parser = tup(
           option("-x", integer()),
           option("-y", integer())
       );

julia> result = argparse(parser, ["-y", "20", "-x", "10"]);

julia> result
(10, 20)

julia> # With label
       parser = tup("coordinates",
           option("-x", integer()),
           option("-y", integer()),
           option("-z", integer())
       );

julia> result = argparse(parser, ["-z", "30", "-x", "10", "-y", "20"]);

julia> result
(10, 20, 30)

julia> # Mixed with arguments
       parser = tup(
           argument(str(metavar="INPUT")),
           option("-o", str()),
           switch("-v")
       );

julia> result = argparse(parser, ["input.txt", "-v", "-o", "output.txt"]);

julia> result
("input.txt", "output.txt", true)

julia> # Accessing tuple elements
       result = argparse(parser, ["file.txt", "-o", "out.txt"]);

julia> result[1]
"file.txt"

julia> result[2]
"out.txt"

julia> result[3]
false
```

# Notes
- Return order is determined by parser definition order, not argument order
- More restrictive than `object` - cannot access results by name
- Useful when you need guaranteed ordering
- Can be nested for complex structures

# See Also
- [`object`](@ref): Named tuple constructor (more flexible)
- [`concat`](@ref): Concatenate multiple tuples
"""
function tup end

tup(parsers...; kw...) = _parser(ConstrTuple(parsers; kw...))
tup(label::String, parsers...; kw...) = _parser(ConstrTuple(parsers; label, kw...))

## Concat

"""
    concat(tups...; label = "", allowDuplicates = false)

Constructor that concatenates multiple tuple parsers into a single flat tuple.

This is useful for composing parsers from reusable tuple components while maintaining
a single flat result structure.

# Arguments
- `tups...`: Multiple tuple parsers to concatenate

# Keywords
- `label::String = ""`: Optional label for the concatenated tuple
- `allowDuplicates::Bool = false`: Whether to allow duplicate parsers in the result

# Returns
A parser that combines all elements from the input tuples into a single flat tuple.

# Examples
```jldoctest
julia> using OptParse

julia> # Reusable tuple components
       positionArgs = tup(
           option("-x", integer()),
           option("-y", integer())
       );

julia> sizeArgs = tup(
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
           tup(option("--host", str())),
           tup(option("--port", integer())),
           label = "connection"
       );

julia> result = argparse(parser, ["--host", "localhost", "--port", "8080"]);

julia> result
("localhost", 8080)

julia> # Multiple concatenations
       headerArgs = tup(option("-H", str()));

julia> bodyArgs = tup(option("-d", str()));

julia> authArgs = tup(option("-u", str()), option("-p", str()));

julia> httpParser = concat(headerArgs, bodyArgs, authArgs, label = "http_request");

julia> result = argparse(httpParser, ["-H", "Content-Type: json", "-d", "data", "-u", "user", "-p", "pass"]);

julia> result
("Content-Type: json", "data", "user", "pass")
```

# Notes
- Results in a flat tuple, not nested tuples
- By default, prevents duplicate parsers (set `allowDuplicates = true` to override)
- Maintains order across all concatenated tuples
- Useful for DRY principle with tuple-based parsers

# See Also
- [`tup`](@ref): Create individual tuples
- [`objmerge`](@ref): Similar operation for object constructors
"""
function concat end

concat(tups...; label = "", allowDuplicates = false) = _parser(ConstrTuple(_concat(tups); label, allowDuplicates))
