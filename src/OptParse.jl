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
    i16,
    i32,
    i64,
    i8,
    integer,
    multiple,
    object,
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

include("utils.jl")
include("core/breadcrumbs.jl")
include("core/context.jl")
include("core/errors.jl")
include("core/parseresult.jl")
include("usage/usage.jl")
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
    origin   = Int[]
    optterm  = false

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


"""
    tryoptparse(parser, argv)

Lower-level parsing entrypoint.

Returns a result object containing either the parsed value or a structured parse failure.
Unlike [`optparse`](@ref), this function does not throw on parse failures.
"""
function tryoptparse(pp::Parser{T, S}, args::Vector{String})::ParseResult{T} where {T, S}

    canonical_argv, _ = normalize_argv(args)
    ctx = Context{S}(buffer=canonical_argv, state=pp.initialState)

    while true
        mayberesult::InnerParseResult{S} = @unionsplit parse(pp, ctx)

        if is_error(mayberesult)
            return typedErr(unwrap_error(mayberesult).error)
        end
        result = unwrap(mayberesult)

        previous_buffer = ctx_remaining(ctx)
        ctx = res_nextctx(result)

        if (
                ctx_length(ctx) > 0
                    && ctx_length(ctx) == length(previous_buffer)
                    && ctx_remaining(ctx) == previous_buffer
            )
            # Top-level progress guard: a parser must not report success while leaving argv unchanged.
            return typedErr(main_error(MAIN_NoProgress; token = ctx_peek(ctx)))
        end

        ctx_length(ctx) > 0 || break
    end

    state = ctx_state(ctx)

    return @unionsplit complete(pp, state)
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

    function optparse(pp::Parser{T}, args::Vector{String})::Union{T, Nothing} where {T}
        mayberes = tryoptparse(pp, args)::ParseResult{T}

        if is_error(mayberes)
            errmsg = sprint(showerror, ParseException(unwrap_error(mayberes)))
            print(Core.stderr, "Error: ")
            println(Core.stderr, errmsg)
            return nothing
        end

        return unwrap(mayberes)
    end

else

    function optparse(pp::Parser{T}, args::Vector{String})::T where {T}
        mayberes = tryoptparse(pp, args)::ParseResult{T}

        if is_error(mayberes)
            throw(ParseException(unwrap_error(mayberes)))
        end

        return unwrap(mayberes)
    end

end



end # module OptParse
