struct OverlayContext
    info::HelpInfo
end

helpinfo(rt::OverlayContext) = rt.info

root_overlay_context() = OverlayContext(HelpInfo())

node_helpinfo(rt::OverlayContext) = rt.info

with_helpinfo(ctx::OverlayContext, info::HelpInfo) =
    set(ctx, (@o _.info), merge_helpinfo(ctx.info, info))

# the help information is Node local, not inherited.
descend_child(ctx::OverlayContext) =
    OverlayContext(HelpInfo())


# ═══════════════════════════════════════════════════════════════════════════════
# Interface validation
#
# AbstractParser subtypes must implement:
#   parse(p, ctx::Context{S}) → InnerParseResult{S}
#   complete(p, state::S) → ParseResult{T, E}
#   usage(p) → UsageNode
#   helpentries(p, rt::OverlayContext) → Vector{HelpEntry}
#   focused_helpdoc(p, ctx::Context, prefix::Vector{String}, rt::OverlayContext) → HelpDoc
#
# AbstractValueParser subtypes must implement:
#   (v)(input::String) → ParseResult{T, E}
#   default_metavar(v) → String
#
# AbstractParseError subtypes must implement:
#   render_error(io::IO, err) → Nothing
# ═══════════════════════════════════════════════════════════════════════════════

"""
    validate(p::AbstractParser)

Check that a parser correctly implements the `AbstractParser` interface.

Verifies that the concrete type has methods for `parse`, `complete`, `usage`,
`helpentries`, and `focused_helpdoc` with the expected signatures.

Throws an error listing any missing methods.
"""
function validate(p::AbstractParser)
    T, E, S = tval(p), terr(p), tstate(p)
    P = typeof(p)
    missing_methods = String[]

    hasmethod(parse, Tuple{P, Context{S}}) ||
        push!(missing_methods, "parse(::$P, ::Context{$S})")
    hasmethod(complete, Tuple{P, S}) ||
        push!(missing_methods, "complete(::$P, ::$S)")
    hasmethod(usage, Tuple{P}) ||
        push!(missing_methods, "usage(::$P)")
    hasmethod(helpentries, Tuple{P, OverlayContext}) ||
        push!(missing_methods, "helpentries(::$P, ::OverlayContext)")
    hasmethod(focused_helpdoc, Tuple{P, Context{S}, Vector{String}, OverlayContext}) ||
        push!(missing_methods, "focused_helpdoc(::$P, ::Context{$S}, ::Vector{String}, ::OverlayContext)")

    if !isempty(missing_methods)
        error(
            "$P is missing the following interface methods:\n" *
            join(("  • " * m for m in missing_methods), "\n")
        )
    end
    return nothing
end

"""
    validate(::Type{E}) where {E <: AbstractParseError}

Check that an error type correctly implements the `AbstractParseError` interface.

Verifies that `render_error(::IO, ::E)` is defined.
"""
function validate(::Type{E}) where {E <: AbstractParseError}
    hasmethod(render_error, Tuple{IO, E}) ||
        error("$E must implement `render_error(io::IO, err::$E)`")
    return nothing
end


include("valueparsers/valueparsers.jl")
include("primitives/primitives.jl")
include("constructors/constructors.jl")
include("modifiers/modifiers.jl")

# modifiers

## Default

"""
    default(p::AbstractParser, value)
    default(value)

Modifier that provides a default value for a parser when it fails to match or is not present
in the command-line arguments.

# Arguments
- `p::AbstractParser`: The parser to apply the default value to
- `value`: The default value to return if parsing fails (can be any type)

# Returns
A modified parser that returns `value` if the original parser fails to match.

# Examples
```jldoctest
julia> using OptParse

julia> # Parser with explicit default
       p = default(option("-p", "--port", integer()), 8080);

julia> result = optparse(p, String[]);

julia> result
8080

julia> result = optparse(p, ["--port", "3000"]);

julia> result
3000

julia> # Curried version for pipeline composition
       p = option("-p", "--port", integer()) |> default(8080);

julia> result = optparse(p, String[]);

julia> result
8080
```

# See Also
- [`optional`](@ref): Convenience wrapper using `nothing` as default
"""
function default end

default(p::AbstractParser, value) = ModWithDefault(p, value)
default(value) = (p::AbstractParser) -> default(p, value)

## Optional

"""
    optional(p::AbstractParser)

Modifier that makes a parser optional, returning `nothing` if the parser fails to match.

Transforms a parser returning type `T` into a parser returning `Union{Nothing, T}`.
This is equivalent to `default(p, nothing)` and is mainly provided as a convenience wrapper.

# Arguments
- `p::AbstractParser`: The parser to make optional

# Returns
A modified parser that returns `nothing` if parsing fails, or the parsed value otherwise.

# Examples
```jldoctest
julia> using OptParse

julia> # Optional option - returns parsed value or nothing
       port = optional(option("-p", "--port", integer()));

julia> result = optparse(port, String[]);

julia> result === nothing
true

julia> result = optparse(port, ["-p", "8080"]);

julia> result
8080
```

# See Also
- [`default`](@ref): More general modifier with custom defaults
"""
function optional end

optional(p::AbstractParser) = default(p, nothing)
optional() = default(nothing)

## Repeated

"""
    repeated(p::AbstractParser; min=0, max=typemax(Int))
    repeated(; min=0, max=typemax(Int))
    many(p::AbstractParser; max=typemax(Int))
    many(; max=typemax(Int))
    many1(p::AbstractParser; max=typemax(Int))
    many1(; max=typemax(Int))

Modifiers that allow a parser to match repeatedly, collecting results in a vector.

Use `many` for zero or more matches, `many1` for one or more matches, and
`repeated` when you need explicit `min` or `max` bounds.

# Arguments
- `p::AbstractParser`: The parser to match repeatedly

# Keywords
- `min::Int`: The minimum amount of times this parser must match
- `max::Int`: The maximum amount of times this parser can match

# Returns
A parser that returns a vector of values, where each value is a successful match of the
original parser.

# Examples
```jldoctest
julia> using OptParse

julia> # Zero or more arguments (e.g., `add pkg1 pkg2 pkg3`)
       packages = many(arg(str("PACKAGE")));

julia> result = optparse(packages, ["pkg1", "pkg2", "pkg3"]);

julia> result
3-element Vector{String}:
 "pkg1"
 "pkg2"
 "pkg3"

julia> # Zero or more switches for verbosity levels (e.g., `-v -v -v`)
       verbosity = many(switch("-v"));

julia> result = optparse(verbosity, ["-v", "-v", "-v"]);

julia> length(result)
3

julia> # One or more arguments
       files = many1(arg(str("FILE")));

julia> optparse(files, ["README.md"])
1-element Vector{String}:
 "README.md"

julia> # Explicit bounds
       includes = repeated(option("-I", str()); min = 1, max = 3);

julia> result = optparse(includes, ["-I", "/usr/include", "-I", "/opt/include"]);

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
function repeated end

"""
    many(p::AbstractParser; max=typemax(Int))
    many(; max=typemax(Int))

Zero-or-more repetition modifier.

This is equivalent to `repeated(p; min = 0, max)`.

# See Also
- [`many1`](@ref): One-or-more repetition
- [`repeated`](@ref): General bounded repetition
"""
function many end

"""
    many1(p::AbstractParser; max=typemax(Int))
    many1(; max=typemax(Int))

One-or-more repetition modifier.

This is equivalent to `repeated(p; min = 1, max)`.

# See Also
- [`many`](@ref): Zero-or-more repetition
- [`repeated`](@ref): General bounded repetition
"""
function many1 end

repeated(p::AbstractParser; kw...) = ModMultiple(p; kw...)
repeated(; kw...) = (p::AbstractParser) -> repeated(p; kw...)

many(p::AbstractParser; max::Integer = typemax(Int)) = repeated(p; min = 0, max)
many(; max::Integer = typemax(Int)) = (p::AbstractParser) -> many(p; max)

many1(p::AbstractParser; max::Integer = typemax(Int)) = repeated(p; min = 1, max)
many1(; max::Integer = typemax(Int)) = (p::AbstractParser) -> many1(p; max)

## Help Information

"""
    help(p::AbstractParser, brief="", description="", footer=""; hidden=false)
    help(brief="", description="", footer=""; hidden=false)

Attach help information to a parser without changing parsing semantics.

`help(...)` can be used either directly or as a pipeline modifier. The information
is consumed by usage and help generation; `parse` and `complete` delegate to the
wrapped parser unchanged.

This is the main way to annotate parsers with user-facing prose. The same parser
tree still defines CLI behavior; `help(...)` only enriches that tree with
documentation.

# Arguments
- `p::AbstractParser`: The parser to annotate
- `brief::String`: Short one-line summary
- `description::String`: Longer help text
- `footer::String`: Footer or epilog text

# Keywords
- `hidden::Bool`: Hide this parser from usage/help output when `true`

# Examples
```jldoctest
julia> using OptParse

julia> parser = record((
           host = option("--host", str("HOST")) |> help("Host", "Hostname to bind"),
           verbose = flag("-v", "--verbose") |> help("Verbose", "Enable verbose logging"),
       ));

julia> result = optparse(parser, ["--host", "localhost", "-v"]);

julia> (result.host, result.verbose)
("localhost", true)
```

# See Also
- [`hidden`](@ref): Convenience modifier for hidden parsers
"""
function help end

function help(
        p::AbstractParser;
        hidden::Bool = false,
        brief::AbstractString = "",
        description::AbstractString = "",
        footer::AbstractString = "",
    )
    info = HelpInfo(; brief = String(brief), description = String(description), footer = String(footer), hidden)

    return ModHelp(p, info)
end

help(
    p::AbstractParser,
    brief::AbstractString;
    hidden::Bool = false,
    description::AbstractString = "",
    footer::AbstractString = "",
) = help(p; hidden, brief, description, footer)

help(
    p::AbstractParser,
    brief::AbstractString,
    description::AbstractString;
    hidden::Bool = false,
    footer::AbstractString = "",
) = help(p; hidden, brief, description, footer)

help(
    p::AbstractParser,
    brief::AbstractString,
    description::AbstractString,
    footer::AbstractString;
    hidden::Bool = false,
) = help(p; hidden, brief, description, footer)

help(; kw...) = (p::AbstractParser) -> help(p; kw...)
help(brief::AbstractString; kw...) = (p::AbstractParser) -> help(p, brief; kw...)
help(brief::AbstractString, description::AbstractString; kw...) =
    (p::AbstractParser) -> help(p, brief, description; kw...)
help(brief::AbstractString, description::AbstractString, footer::AbstractString; kw...) =
    (p::AbstractParser) -> help(p, brief, description, footer; kw...)

"""
    hidden(p::AbstractParser)
    hidden()

Hide a parser from usage/help output without changing parsing semantics.

This is equivalent to `help(p; hidden=true)` and supports pipeline style via
`hidden()`. Hidden parsers still participate in parsing and still contribute
their values to the final result.

# Examples
```jldoctest
julia> using OptParse

julia> parser = record((debug = flag("--debug") |> hidden(), file = arg(str("FILE"))));

julia> optparse(parser, ["--debug", "input.txt"]).debug
true

julia> OptParse.render_usage(OptParse.usage(parser))
"<FILE>"
```

# See Also
- [`help`](@ref): General help information modifier
"""
function hidden end

hidden(p::AbstractParser) = help(p; hidden = true)
hidden() = (p::AbstractParser) -> hidden(p)

"""
    construct(::Type{T}, parser)
    construct(::Type{T})(parser)
    construct(::Type{T}, record_fields::NamedTuple)
    construct(::Type{T}, sequence_fields::Tuple)

Wrap a parser and construct values of type `T` from its completed result using
`StructUtils.make`.

`construct` is intended for child parsers that complete to record-like or
sequence-like values, most commonly [`record`](@ref) and [`sequence`](@ref).
Parsing delegates to the wrapped parser unchanged; type construction happens in
the `complete` phase.

# Examples
```jldoctest
julia> using OptParse

julia> struct Config
           host::String
           port::Int
       end

julia> parser = construct(Config, (
           host = option("--host", str("HOST")),
           port = option("--port", integer("PORT")),
       ));

julia> optparse(parser, ["--host", "localhost", "--port", "8080"])
Config("localhost", 8080)
```

# See Also
- [`record`](@ref)
- [`sequence`](@ref)
- [`construct_exact`](@ref)
"""
function construct end

construct(::Type{T}, p::AbstractParser) where {T} = ModConstruct(p, T)
construct(::Type{T}) where {T} = (x::Union{NamedTuple, Tuple, AbstractParser}) -> construct(T, x)

construct(::Type{T}, nt::NamedTuple) where {T} = ModConstruct(record(nt), T)
construct(::Type{T}, t::Tuple) where {T} = ModConstruct(sequence(t), T)

"""
    construct_exact(::Type{T}, parser)
    construct_exact(::Type{T})(parser)
    construct_exact(::Type{T}, record_fields::NamedTuple)
    construct_exact(::Type{T}, sequence_fields::Tuple)

Wrap a parser and construct values of type `T` using exact field or positional
matching instead of `StructUtils.make`.

`construct_exact` is intended for concrete struct types whose fields line up
exactly with the child parser output:

- record children must have the same field names, in the same order, as `T`
- sequence children must have the same arity and positional types as `T`

This stricter path is useful when you want predictable construction behavior and
better trimming compatibility.

The main use of this is through the `@parser` macro. But it is possible to
create it by hand for already existing types. The macro does not support
parametric types, but manual construction does.

# Examples
```jldoctest
julia> using OptParse

julia> struct Point{T}
           x::T
           y::T
       end

julia> parser = construct_exact(Point{Int}, (
           x = option("--x", integer("X")),
           y = option("--y", integer("Y")),
       ));

julia> optparse(parser, ["--x", "10", "--y", "20"])
Point{Int64}(10, 20)
```

# See Also
- [`construct`](@ref)
- [`record`](@ref)
- [`sequence`](@ref)
- [`@parser`](@ref)
"""
function construct_exact end

construct_exact(::Type{T}, p::AbstractParser) where {T} = ModConstructExact(p, T)
construct_exact(::Type{T}) where {T} = (x::Union{NamedTuple, Tuple, AbstractParser}) -> construct_exact(T, x)

construct_exact(::Type{T}, nt::NamedTuple) where {T} = ModConstructExact(record(nt), T)
construct_exact(::Type{T}, t::Tuple) where {T} = ModConstructExact(sequence(t), T)

_parser_apply_leading_help(p::AbstractParser, text::AbstractString) = help(p; description = String(text))
_parser_apply_leading_help(p::AbstractParser, modifier) = modifier(p)

_parser_apply_trailing_help(p::AbstractParser, text::AbstractString) = help(p; footer = String(text))
_parser_apply_trailing_help(p::AbstractParser, modifier) = modifier(p)

function _parser_macro_expand(typeexpr, description, body, footer)
    typeexpr isa Symbol || throw(ArgumentError("@parser currently only supports non-parametric type names."))
    leading_help_ref = GlobalRef(OptParse, :_parser_apply_leading_help)
    trailing_help_ref = GlobalRef(OptParse, :_parser_apply_trailing_help)

    stmts = body isa Expr && body.head == :block ? body.args : Any[body]
    field_defs = Any[]
    parser_fields = Any[]
    parser_bindings = Any[]
    pending_help = nothing

    for stmt in stmts
        stmt isa LineNumberNode && continue

        if stmt isa String
            pending_help === nothing || throw(ArgumentError("Unexpected consecutive help strings in @parser body."))
            pending_help = stmt
            continue
        end

        if stmt isa Expr && stmt.head == :macrocall && length(stmt.args) >= 4 && stmt.args[end - 1] isa String
            pending_help === nothing || throw(ArgumentError("Unexpected consecutive help strings in @parser body."))
            pending_help = stmt.args[end - 1]
            stmt = stmt.args[end]
        end

        stmt isa Expr && stmt.head == :(=) || throw(ArgumentError("@parser body only supports string literals and `field = parser` definitions."))
        lhs, rhs = stmt.args
        lhs isa Symbol || throw(ArgumentError("@parser fields must be written as `field = parser`."))
        name = lhs

        parser_name = gensym(Symbol(name, "_parser"))

        parser_rhs = if isnothing(pending_help)
            rhs
        else
            :($(rhs) |> help($(pending_help)))
        end
        push!(parser_bindings, :(const $(parser_name) = $(parser_rhs)))
        push!(field_defs, :($(name)::valuetype($(parser_name))))
        push!(parser_fields, Expr(:kw, name, parser_name))
        pending_help = nothing
    end

    isnothing(pending_help) || throw(ArgumentError("@parser body ended with a help string that does not apply to any field."))

    parser_expr = :(construct_exact($(typeexpr), (; $(parser_fields...))))
    !isnothing(description) && (parser_expr = Expr(:call, leading_help_ref, parser_expr, description))
    !isnothing(footer) && (parser_expr = Expr(:call, trailing_help_ref, parser_expr, footer))

    return quote
        $(parser_bindings...)
        struct $(typeexpr)
            $(field_defs...)
        end
        $parser_expr
    end
end

"""
    @parser TypeName begin
        "Field help"
        field = parser_expr
        ...
    end

    @parser "Parser description" TypeName begin
        "Field help"
        field = parser_expr
        ...
    end

    @parser "Parser description" TypeName begin
        "Field help"
        field = parser_expr
        ...
    end "Parser footer"

Define a concrete struct and return a matching [`construct_exact`](@ref) parser.

Each field definition in the block becomes both:

- a field in `struct TypeName`
- a field in the generated record parser

The generated struct field types are derived from the parser expressions via
[`valuetype`](@ref), so the struct shape always matches the parser output.

If a string literal appears immediately before a field definition, it is lowered
to `|> help("...")` on that field parser.

If an expression appears before the type name, it is treated as parser-level
description/help metadata. String values are lowered to
`|> help(description = ...)`; other values are applied as parser modifiers.

If an expression appears after the block, it is treated as parser-level
footer/help metadata. String values are lowered to `|> help(footer = ...)`;
other values are applied as parser modifiers.

The parser expressions on the right-hand side are used as-is, so this macro is
mainly syntax sugar over ordinary OptParse combinators.

# Examples
```jldoctest
julia> using OptParse

julia> parser = @parser "Server configuration" Config begin
           "Host"
           host = option("--host", str("HOST"))
           "Port"
           port = option("--port", integer("PORT"))
       end "Server configuration parser";

julia> optparse(parser, ["--host", "localhost", "--port", "8080"])
Config("localhost", 8080)
```

# See Also
- [`construct_exact`](@ref)
- [`construct`](@ref)
"""
macro parser(typeexpr, body)
    return esc(_parser_macro_expand(typeexpr, nothing, body, nothing))
end

macro parser(description, typeexpr, body)
    return esc(_parser_macro_expand(typeexpr, description, body, nothing))
end

macro parser(description, typeexpr, body, footer)
    return esc(_parser_macro_expand(typeexpr, description, body, footer))
end

# @parser MyType{M} begin

#     "this is a docstring"
#     a = option("-i", integer())

#     "this is another docstring"
#     b = option("-j", integer())

# end "Parser footer"

# struct MyType{M}
#     a::M
#     b::Int
# end

# MyType_parser
# = construct(MyType, (;
#     a = or(option("-i", integer()), option("-f", flt()))
#     b = option("-j", integer())
# ))


# primitives

## Option

"""
    option(names..., valparser::AbstractValueParser{T}) where {T}

Primitive parser that matches command-line options with associated values.

Options can be specified in several formats:
- Long form: `--option value` or `--option=value`
- Short form: `-o value`

# Arguments
- `names`: One or more option names (strings). Typically includes short (`"-o"`) and/or
  long (`"--option"`) forms. Can be provided as individual arguments or as a tuple.
- `valparser::AbstractValueParser{T}`: Value parser that determines how to parse the option's value

# Returns
A parser that matches the specified option patterns and returns a value of type `T`.

# Examples
```jldoctest
julia> using OptParse

julia> # Single long option
       port = option("--port", integer());

julia> result = optparse(port, ["--port", "8080"]);

julia> result
8080

julia> # Short and long forms
       port = option("-p", "--port", integer());

julia> result = optparse(port, ["-p", "3000"]);

julia> result
3000

julia> result = optparse(port, ["--port", "3000"]);

julia> result
3000

julia> # With equals sign
       result = optparse(port, ["--port=3000"]);

julia> result
3000

julia> # With constraints
       level = option("-l", "--level", choice(["debug", "info", "warn"]));

julia> result = optparse(level, ["-l", "debug"]);

julia> result
"DEBUG"

julia> @enum Mode begin
           Debug
           Release
       end

julia> mode = option("--mode", choice(Mode));

julia> optparse(mode, ["--mode", "release"])
Release::Mode = 1
```

# Notes
- The first matching pattern is used
- `=` attachment is supported for long options only
- Option names should include their prefix (`-` or `--`)
"""
function option end

option(names::Tuple{Vararg{String}}, valparser::AbstractValueParser) =
    ArgOption(names, valparser)
option(opt1::String, valparser::AbstractValueParser) =
    ArgOption((opt1,), valparser)
option(opt1::String, opt2::String, valparser::AbstractValueParser) =
    ArgOption((opt1, opt2), valparser)
option(opt1::String, opt2::String, opt3::String, valparser::AbstractValueParser) =
    ArgOption((opt1, opt2, opt3), valparser)

option(names::Tuple{Vararg{String}}) = (valp::AbstractValueParser) -> option(names, valp)

## Switch

"""
    switch(names...)

Primitive parser that requires a boolean flag to be present.

Switches represent required flag markers used to activate features or guard specific
subtrees. When present in arguments, they indicate `true`; when absent, parsing fails
(unless wrapped with modifiers like `optional` or `default`).

# Arguments
- `names...`: One or more flag names (strings). Can include short (`"-v"`) and/or
  long (`"--verbose"`) forms

# Returns
A parser that returns `true` when the flag is present.

# Examples
```jldoctest
julia> using OptParse

julia> # Simple switch
       experimental = switch("--experimental");

julia> result = optparse(experimental, ["--experimental"]);

julia> result
true

julia> # Repeated names
       debug = switch("-d", "--debug");

julia> result = optparse(debug, ["-d"]);

julia> result
true

julia> result = optparse(debug, ["--debug"]);

julia> result
true

```

# Notes
- By itself, `switch` requires the flag to be present (fails if absent)
- Use `flag` for optional boolean flags that default to `false`
- Supports bundled short options (e.g., `-abc` equivalent to `-a -b -c`)

# See Also
- [`flag`](@ref): Optional flag that defaults to `false`
"""
function switch end

switch(names...) = ArgGate(names)

## Flag

"""
    flag(names...)

Convenience function for an optional flag that defaults to `false`.

This is equivalent to `default(switch(names...), false)`. When the flag is
present in arguments, it returns `true`; when absent, it returns `false`.

# Arguments
- `names...`: One or more flag names (strings)

# Returns
A parser that returns `true` if the flag is present, `false` otherwise.

# Examples
```jldoctest
julia> using OptParse

julia> # Basic usage
       verbose = flag("-v", "--verbose");

julia> result = optparse(verbose, String[]);

julia> result
false

julia> result = optparse(verbose, ["-v"]);

julia> result
true

julia> # In an record parser
       parser = record((
           help = flag("-h", "--help"),
           version = flag("--version"),
           quiet = flag("-q", "--quiet")
       ));

julia> result = optparse(parser, ["-h", "--version"]);

julia> (result.help, result.version, result.quiet)
(true, true, false)

julia> verbosity = many(switch("-v")); # Repeated verbosity levels

julia> result = optparse(verbosity, ["-v", "-v", "-v"]);

julia> result
3-element Vector{Bool}:
 1
 1
 1
```

# Implementation Note
This is implemented as: `default(switch(names...), false)`

# See Also
- [`switch`](@ref): Required flag that fails if absent
- [`default`](@ref): General modifier for default values
"""
function flag end

flag(names...) = default(ArgGate(names), false)

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
       addCmd = command("add", record((
           action = @constant(:add),
           key = arg(str("KEY")),
           value = arg(str("VALUE"))
       )));

julia> removeCmd = command("remove", record((
           action = @constant(:remove),
           key = arg(str("KEY"))
       )));

julia> parser = or(addCmd, removeCmd);

julia> result = optparse(parser, ["add", "username", "alice"]);

julia> result.action
Val{:add}()

julia> result.key
"username"

julia> result.value
"alice"

julia> # Providing metadata
       parser2 = record((
           version = @constant(Symbol("1.0.0")),
           name = arg(str())
       ));

julia> result = optparse(parser2, ["myapp"]);

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
    return :(ArgConstant($val))
end

## Arg

"""
    arg(valparser::AbstractValueParser{T}) where {T}

Primitive parser for positional arguments not associated with a flag or option.

Arguments are parsed based on their position in the command line and must appear
in the order they're defined (though they can be interspersed with options).

# Arguments
- `valparser::AbstractValueParser{T}`: Value parser that determines how to parse the argument's value

# Returns
A parser that matches a positional argument and returns a value of type `T`.

# Examples
```jldoctest
julia> using OptParse

julia> # Single argument
       source = arg(str("SOURCE"));

julia> result = optparse(source, ["/path/to/file"]);

julia> result
"/path/to/file"

julia> # Repeated positional arguments
       parser = record((
           source = arg(str("SOURCE")),
           dest = arg(str("DEST"))
       ));

julia> result = optparse(parser, ["/from/here", "/to/here"]);

julia> result.source
"/from/here"

julia> result.dest
"/to/here"

julia> # Variable number of arguments
       files = many(arg(str("FILE")));

julia> result = optparse(files, ["file1.txt", "file2.txt", "file3.txt"]);

julia> result
3-element Vector{String}:
 "file1.txt"
 "file2.txt"
 "file3.txt"

julia> # Arguments with type constraints
       port = arg(integer(min=1000, max=65535));

julia> result = optparse(port, ["8080"]);

julia> result
8080

julia> # Mixed with options (order flexible)
       parser = record((
           input = arg(str("INPUT")),
           output = option("-o", "--output", str()),
           verbose = flag("-v")
       ));

julia> result = optparse(parser, ["input.txt", "-o", "output.txt", "-v"]);

julia> result.input
"input.txt"

julia> result = optparse(parser, ["-v", "input.txt", "-o", "output.txt"]);

julia> result.input
"input.txt"
```

# Notes
- Arguments must be present unless wrapped with `optional` or `default`
- The `metavar` in the value parser is used in diagnostics and usage output
- Arguments are parsed in order but can be interspersed with options
- After `--`, remaining tokens are treated as positional input
"""
function arg end

arg(valparser::AbstractValueParser) = ArgArgument(valparser)
arg() = (valp::AbstractValueParser) -> arg(valp)

## command

"""
    command(name::String, p::AbstractParser)
    command(name::String, alias::String, p::AbstractParser)

Primitive parser that matches a subcommand and its associated arguments.

Commands are a hybrid between an option and a constructor - they match a specific
keyword and then delegate to another parser for the remaining arguments. This is
the primary way to implement subcommands in CLI applications.

# Arguments
- `name::String`: The command name to match
- `p::AbstractParser`: The parser to use for arguments following the command

# Returns
A parser that matches the command name and then parses the remaining arguments
using the provided parser.

# Examples
```jldoctest
julia> using OptParse

julia> # Simple command
       instantiate = command("instantiate", record((
           verbose = flag("-v", "--verbose"),
           manifest = flag("-m", "--manifest")
       )));

julia> result = optparse(instantiate, ["instantiate", "-v", "-m"]);

julia> (result.verbose, result.manifest)
(true, true)

julia> # Repeated commands with or combinator
       addCmd = command("add", record((
           action = @constant(:add),
           packages = many(arg(str("PACKAGE")))
       )));

julia> removeCmd = command("remove", record((
           action = @constant(:remove),
           packages = many(arg(str("PACKAGE")))
       )));

julia> pkgParser = or(addCmd, removeCmd);

julia> result = optparse(pkgParser, ["add", "OptParse", "DataFrames"]);

julia> result.action
Val{:add}()

julia> result.packages
2-element Vector{String}:
 "OptParse"
 "DataFrames"

julia> result = optparse(pkgParser, ["remove", "OldPkg"]);

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

command(names::Tuple{Vararg{String}}, p::AbstractParser) = ArgCommand(names, p)
command(name::String, p::AbstractParser) = ArgCommand((name,), p)
command(name::String, alias::String, p::AbstractParser) = ArgCommand((name, alias), p)

## helpcommand

"""
    helpcommand()
    helpcommand(name::String)
    helpcommand(name::String, alias::String)
    helpcommand(names::Tuple{Vararg{String}})

Convenience parser for an explicit top-level help command.

`helpcommand()` behaves like a subcommand parser rooted at `"help"`. It
collects any following positional tokens as a help scope and completes to
[`HelpRequest`](@ref), which can later be handled by a higher-level runner.

This parser does not render help by itself. It only parses and returns the
requested help scope.

This parser is available as a normal public building block and can be used
inside ordinary parser trees. Higher-level entrypoints such as [`runparse`](@ref)
may also inject it automatically at the top level.

# Examples
```jldoctest
julia> using OptParse

julia> req = optparse(helpcommand(), ["help", "remote", "add"]);

julia> req isa HelpRequest
true

julia> req.argv
2-element Vector{String}:
 "remote"
 "add"
```

# See Also
- [`command`](@ref)
- [`generate_help`](@ref)
- [`runparse`](@ref)
"""
function helpcommand end

helpcommand() = helpcommand("help")
helpcommand(names::Tuple{Vararg{String}}) =
    command(
    names,
    construct(HelpRequest, (; argv = many(arg(str("COMMAND")))))
) |> help("Show help for a command or subcommand")
helpcommand(name::String) = helpcommand((name,))
helpcommand(name::String, alias::String) = helpcommand((name, alias))


# constructors

## Record

"""
    record(obj::NamedTuple)
    record(objlabel, obj::NamedTuple)

Constructor that creates a parser from a named tuple of parsers, returning a named tuple
of parsed values.

This is the primary way to combine several parsers into a cohesive structure. Each field
in the named tuple should be a parser, and the result will be a named tuple with the same
field names containing the parsed values.

# Arguments
- `obj::NamedTuple`: Named tuple where each field is a parser
- `objlabel`: Optional label used in diagnostics and stored as record metadata

# Returns
A parser that returns a named tuple with the same structure as `obj`, where each field
contains the parsed result from the corresponding parser.

# Examples
```jldoctest
julia> using OptParse

julia> # Basic usage
       parser = record((
           name = option("-n", "--name", str()),
           port = option("-p", "--port", integer()),
           verbose = flag("-v")
       ));

julia> result = optparse(parser, ["-n", "server", "-p", "8080", "-v"]);

julia> result.name
"server"

julia> result.port
8080

julia> result.verbose
true

julia> parser = record("config", (
           host = option("--host", str()),
           port = option("--port", integer())
       )); # With a label for clearer diagnostics

julia> result = optparse(parser, ["--host", "localhost", "--port", "3000"]);

julia> result.host
"localhost"

julia> parser = record((
           server = record((
               host = option("--host", str()),
               port = option("--port", integer())
           )),
           timeout = option("--timeout", integer())
       ));  # Nested records

julia> result = optparse(parser, ["--host", "localhost", "--port", "8080", "--timeout", "30"]);

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
- [`combine`](@ref): Combine multiple records into one
- [`sequence`](@ref): Ordered tuple constructor
"""
function record end

record(obj::NamedTuple) = ConstrObject(obj)
record(objlabel, obj::NamedTuple) = ConstrObject(obj; label = objlabel)

## Combine

"""
    combine(objs...)
    combine(label::String, objs...)

Constructor that combines several record parsers into a single parser.

This is useful for composing parsers from reusable components or for organizing
large parser definitions into logical groups.

# Arguments
- `label::String = ""`: Optional label used in diagnostics and stored as object metadata
- `objs...`: Repeated record parsers to merge


# Returns
A parser that combines all fields from the input records into a single result.

# Examples
```jldoctest
julia> using OptParse

julia> # Reusable parser components
       commonOpts = record((
           verbose = flag("-v", "--verbose"),
           quiet = flag("-q", "--quiet")
       ));

julia> networkOpts = record((
           host = option("--host", str()),
           port = option("--port", integer())
       ));

julia> # Merge into single parser
       parser = combine(commonOpts, networkOpts);

julia> result = optparse(parser, ["-v", "--host", "localhost", "--port", "8080"]);

julia> result.verbose
true

julia> result.host
"localhost"

julia> result.port
8080

julia> # With label
       parser = combine("server_options", commonOpts, networkOpts);

julia> result = optparse(parser, ["--host", "127.0.0.1", "--port", "3000", "-v"]);

julia> result.host
"127.0.0.1"
```

# Notes
- Field names must be unique across all merged records
- Duplicate field names will cause an error
- Maintains type stability
- Useful for DRY (Don't Repeat Yourself) principle in parser definitions

# See Also
- [`record`](@ref): Create parser from single named tuple
- [`concat`](@ref): Similar operation for sequence constructors
"""
function combine end


combine(objs...) = ConstrObject(_merge(objs))
combine(label::String, objs...) = ConstrObject(_merge(objs); label)

## Or

"""
    or(parsers...)

Combinator that creates a parser matching exactly one of the provided parsers.

The `or` combinator tries each parser in sequence and succeeds with the first one
that matches. All parsers are mutually exclusive - only one can succeed. This is
the primary way to implement subcommands or alternative parsing branches.

`or(...)` is order-dependent: branches are tried in the order they are listed,
and the first semantic match wins. Put broader positional parsers like
`arg(...)` or `many(arg(...))` last.

# Arguments
- `parsers...`: Variable number of parsers to try in order

# Returns
A parser that returns the result of the first successfully matching parser.

# Examples
```jldoctest
julia> using OptParse

julia> # Subcommands
       addCmd = command("add", record((
           action = @constant(:add),
           packages = many(arg(str("PACKAGE")))
       )));

julia> removeCmd = command("remove", record((
           action = @constant(:remove),
           packages = many(arg(str("PACKAGE")))
       )));

julia> parser = or(addCmd, removeCmd);

julia> result = optparse(parser, ["add", "Package1", "Package2"]);

julia> result.action
Val{:add}()

julia> result.packages
2-element Vector{String}:
 "Package1"
 "Package2"

julia> result = optparse(parser, ["remove", "OldPackage"]);

julia> result.action
Val{:remove}()

julia> # Alternative formats
       helpFormat = or(
           switch("-h"),
           switch("--help"),
           switch("-?")
       );

julia> result = optparse(helpFormat, ["-h"]);

julia> result
true

julia> result = optparse(helpFormat, ["--help"]);

julia> result
true

julia> # Different configuration modes
       config = or(
           record((mode = @constant(:file), file = option("-f", str()))),
           record((mode = @constant(:inline), config = option("-c", str())))
       );

julia> result = optparse(config, ["-f", "config.toml"]);

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

or(parsers...) = ConstrOr(parsers)


## Sequence

"""
    sequence(parsers...; kw...)
    sequence(label::String, parsers...; kw...)

Constructor that creates an ordered sequence parser from several parsers.

Similar to `record` but maintains argument order and returns a tuple instead of
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

julia> result = optparse(parser, ["-y", "20", "-x", "10"]);

julia> result
(10, 20)

julia> # With label
       parser = sequence("coordinates",
           option("-x", integer()),
           option("-y", integer()),
           option("-z", integer())
       );

julia> result = optparse(parser, ["-z", "30", "-x", "10", "-y", "20"]);

julia> result
(10, 20, 30)

julia> # Mixed with arguments
       parser = sequence(
           arg(str("INPUT")),
           option("-o", str()),
           switch("-v")
       );

julia> result = optparse(parser, ["input.txt", "-v", "-o", "output.txt"]);

julia> result
("input.txt", "output.txt", true)

```

# Notes
- Return order is determined by parser definition order, not argument order
- More restrictive than `record` - cannot access results by name
- Useful when you need guaranteed ordering
- Can be nested for complex structures

# See Also
- [`record`](@ref): Named tuple constructor (more flexible)
- [`concat`](@ref): Concatenate multiple sequences
"""
function sequence end

sequence(parsers...; kw...) = ConstrTuple(parsers; kw...)
sequence(parsers::Tuple{Vararg{AbstractParser}}; kw...) = ConstrTuple(parsers; kw...)
sequence(label::String, parsers...; kw...) = ConstrTuple(parsers; label, kw...)
sequence(label::String, parsers::Tuple{Vararg{AbstractParser}}; kw...) = ConstrTuple(parsers; label, kw...)

## Concat

"""
    concat(seqs...; label = "")

Constructor that concatenates several sequence parsers into a single flat tuple.

This is useful for composing parsers from reusable sequence components while maintaining
a single flat result structure.

# Arguments
- `seqs...`: Repeated sequence parsers to concatenate

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

julia> result = optparse(parser, ["-x", "10", "-y", "20", "--width", "100", "--height", "50"]);

julia> result
(10, 20, 100, 50)

julia> # With label
       parser = concat(
           sequence(option("--host", str())),
           sequence(option("--port", integer())),
           label = "connection"
       );

julia> result = optparse(parser, ["--host", "localhost", "--port", "8080"]);

julia> result
("localhost", 8080)

julia> # Repeated concatenations
       headerArgs = sequence(option("-H", str()));

julia> bodyArgs = sequence(option("-d", str()));

julia> authArgs = sequence(option("-u", str()), option("-p", str()));

julia> httpParser = concat(headerArgs, bodyArgs, authArgs, label = "http_request");

julia> result = optparse(httpParser, ["-H", "Content-Type: json", "-d", "data", "-u", "user", "-p", "pass"]);

julia> result
("Content-Type: json", "data", "user", "pass")
```

# Notes
- Results in a flat tuple, not nested tuples
- Maintains order across all concatenated sequences
- Useful for DRY principle with sequence-based parsers

# See Also
- [`sequence`](@ref): Create individual sequences
- [`combine`](@ref): Similar operation for record constructors
"""
function concat end

concat(seqs...; label = "") = ConstrTuple(_concat(seqs); label)
