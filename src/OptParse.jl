module OptParse

# Check whether we are compiling with juliac
using Preferences: @load_preference
const juliac = @load_preference("juliac", false)

using Accessors: @o, IndexLens, PropertyLens, insert, set

using WrappedUnions: @unionsplit, @wrapped,
    #=conflicts with the unwrap from ErrorTypes.jl=#
    unwrap as unwrapunion

using ErrorTypes: @?, Err, ErrorTypes, Ok, Option, Result, base, is_error,
    none, some, unwrap, unwrap_error

using UUIDs:
    UUID,
    uuid_version

export
    @?,
    @constant,
    arg,
    optparse,
    choice,
    combine,
    concat,
    command,
    default,
    flag,
    flt,
    flt32,
    flt64,
    gate,
    generate_help,
    help,
    hidden,
    i16,
    i32,
    i64,
    i8,
    integer,
    multiple,
    record,
    option,
    optional,
    or,
    path,
    resulttype,
    str,
    tryoptparse,
    sequence,
    u16,
    u32,
    u64,
    u8,
    uuid

public build_help_doc, render_helpdoc


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

julia> greet = command("greet", record((
           cmd = @constant(:greet),
           name = option("-n", str("NAME")),
       )));

julia> const Greet = resulttype(greet);

julia> Greet
@NamedTuple{cmd::Val{:greet}, name::String}
```

A common pattern is to define a stable alias once and dispatch on it later

# See Also
- [`optparse`](@ref)
- [`tryoptparse`](@ref)
"""
resulttype(::Type{<:AbstractParser{T}}) where {T} = T
resulttype(::AbstractParser{T}) where {T} = T

include("utils.jl")
include("core/usage/usage.jl")
include("core/help/help.jl")
include("core/context.jl")
include("core/errors.jl")
include("core/parseresult.jl")
include("parsers/parser.jl")
include("display/parser_show.jl")


"""
    normalize_argv(argv) -> (expanded, origin)

Expands bundled boolean short flags:
    "-abc" -> "-a", "-b", "-c"

Rules:
- Only expand before `--`
- Do not expand tokens starting with "--"
- After `--`, tokens are untouched

Returns:
- expanded::Vector{String}
- origin::Vector{Int}  (expanded index -> original argv index)
"""
function normalize_argv(argv::Vector{String})
    expanded = String[]
    origin = Int[]
    optterm = false

    for (i, tok) in pairs(argv)
        if tok == "--"
            optterm = true
            push!(expanded, tok); push!(origin, i)
            continue
        end

        if !optterm && startswith(tok, "-") && !startswith(tok, "--") && lastindex(tok) > 2
            # "-abc" => "-a","-b","-c"
            for c in tok[2:end]
                push!(expanded, "-" * string(c))
                push!(origin, i)
            end
        else
            push!(expanded, tok); push!(origin, i)
        end
    end

    return expanded, origin
end


function no_progress(previous_buffer, ctx)
    return ctx_length(ctx) > 0 &&
        ctx_length(ctx) == length(previous_buffer) &&
        ctx_remaining(ctx) == previous_buffer
end


function recover_usage_context(pp::AbstractParser{T, S}, argv::Vector{String})::Context{S} where {T, S}
    canonical_argv, _ = normalize_argv(argv)
    ctx = Context{S}(buffer = canonical_argv, state = pp.initialState, usage = @unionsplit usage(pp))

    while true
        mayberesult::InnerParseResult{S} = @unionsplit parse(pp, ctx)

        if is_error(mayberesult)
            return ctx
        end
        result = unwrap(mayberesult)

        previous_buffer = ctx_remaining(ctx)
        ctx = res_nextctx(result)

        if no_progress(previous_buffer, ctx)
            # Top-level progress guard: a parser must not report success while leaving argv unchanged.
            return ctx
        end

        ctx_length(ctx) > 0 || break
    end

    return ctx
end

"""
    build_help_doc(parser, argv)

Build a focused help document for `argv` from `parser`.

This is a structured, cold-path helper used by OptParse's help and error
rendering machinery. It replays enough parser state to determine the most
relevant help scope, then returns a [`HelpDoc`](@ref) for that scope.

Unlike `generate_help`, this function returns the intermediate help document
rather than rendered text. It is useful if you want to inspect or render the
focused help information yourself.

# Examples
```jldoctest
julia> using OptParse

julia> parser = command("serve", record((
           host = option("--host", str("HOST")),
           verbose = flag("-v", "--verbose"),
       )));

julia> doc = OptParse.build_help_doc(parser, ["serve", "--unknown"]);

julia> doc.prefix
1-element Vector{String}:
 "serve"
```

# See Also
- `generate_help`
- `OptParse.render_helpdoc`
"""
function build_help_doc(parser, argv)
    ctx = recover_usage_context(parser, argv)
    return @unionsplit focused_helpdoc(parser, ctx, String[], root_overlay_context())::HelpDoc
end

"""
    generate_help(parser, argv; progname = "")

Generate a rendered help page for `argv` from `parser`.

This is a high-level convenience wrapper around `build_help_doc` and
`OptParse.render_helpdoc`. It does not decide when help should be shown; it only
derives and renders the focused help page for the given parser and argument
vector.

This is useful if you want to handle `--help`, help subcommands, or other
application-specific help triggers yourself while still reusing OptParse's help
generation.

# Keyword Arguments
- `progname::AbstractString = ""`: Program name prefix to render in the usage line

# Examples
```jldoctest
julia> using OptParse

julia> parser = command("serve", record((
           host = option("--host", str("HOST")),
           verbose = flag("-v", "--verbose"),
       )));

julia> print(OptParse.generate_help(parser, ["serve"]; progname = "prog"))

Usage: prog serve --host <HOST> [OPTIONS]

Options:
   --host <HOST>
   [--verbose]

```

# See Also
- `build_help_doc`
- [`optparse`](@ref)
- [`tryoptparse`](@ref)
"""
generate_help(parser, argv; progname = "") = render_helpdoc(build_help_doc(parser, argv); progname)

"""
    tryoptparse(parser, argv)

Lower-level parsing entrypoint.

Returns a result container containing either the parsed value or a structured parse failure.
Unlike [`optparse`](@ref), this function does not throw on parse failures.
"""
function tryoptparse(pp::AbstractParser{T, S}, args::Vector{String})::ParseResult{T} where {T, S}

    canonical_argv, _ = normalize_argv(args)
    ctx = Context{S}(buffer = canonical_argv, state = pp.initialState, usage = @unionsplit usage(pp))

    while true
        mayberesult::InnerParseResult{S} = @unionsplit parse(pp, ctx)

        if is_error(mayberesult)
            return typedErr(unwrap_error(mayberesult).error)
        end
        result = unwrap(mayberesult)

        previous_buffer = ctx_remaining(ctx)
        ctx = res_nextctx(result)

        if no_progress(previous_buffer, ctx)
            # Top-level progress guard: a parser must not report success while leaving argv unchanged.
            return typedErr(T, main_error(MAIN_NoProgress; token = ctx_peek(ctx)))
        end

        ctx_length(ctx) > 0 || break
    end

    state = ctx_state(ctx)

    ret = @unionsplit complete(pp, state)
    return ret
end

"""
    optparse(parser, argv)

High-level parsing entrypoint.

This function has two modes controlled through the `juliac` preference loaded
via `Preferences.jl`:

- in normal Julia runtime usage, it returns the parsed value and throws
  [`ParseException`](@ref) on failure
- when `juliac` mode is enabled, it renders the error to `stderr` and returns
  `nothing` on failure instead of throwing

If you need stable non-throwing behavior across environments, use
[`tryoptparse`](@ref) instead.
"""
@static if juliac

    function optparse(pp::AbstractParser{T}, args::Vector{String})::Union{T, Nothing} where {T}
        mayberes = tryoptparse(pp, args)::ParseResult{T}

        if is_error(mayberes)
            errmsg = sprint(
                showerror, ParseException(
                    pp,
                    args,
                    unwrap_error(mayberes)
                )
            )

            print(Core.stderr, "Error: ")
            println(Core.stderr, errmsg)
            return nothing
        end

        return unwrap(mayberes)
    end

else

    function optparse(pp::AbstractParser{T}, args::Vector{String})::T where {T}
        mayberes = tryoptparse(pp, args)::ParseResult{T}

        if is_error(mayberes)
            throw(
                ParseException(
                    pp,
                    args,
                    unwrap_error(mayberes)
                )
            )
        end

        return unwrap(mayberes)
    end

end


end # module OptParse
