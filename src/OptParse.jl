module OptParse

using Accessors: @o, IndexLens, PropertyLens, insert, set

using WrappedUnions: @unionsplit, @wrapped,
    #=conflicts with the unwrap from ErrorTypes.jl=#
    unwrap as unwrapunion

using ErrorTypes: @?, Err, ErrorTypes, Ok, Option, Result, base, is_error,
    none, some, unwrap, unwrap_error

using UUIDs:
    UUID,
    uuid_version

# based on: https://optique.dev/concepts

# value parsers: specialized components that convert raw string into desired outputs
#	OK string(pattern) OK
#	OK integer(min, max, type)
#	OK float(min, max, allowInfinity, allowNan)
#	OK choice([list of choices], caseinsensitive)
#	- uri() # also this one shold be easy?
#	OK uuid() # this one is easy
#	- path() # might be a bit out of scope
#   is the Dates stdlib trimmable?
#	- instant() # moment in time
#	- duration() # minutes or seconds.
#	- zone-datetime() # needs external package, so no go

#	- datetime() # what's the difference with instant()?
#   these could just be special cases of the above with different formats.
#	- yearmonth() # half a date
#	- monthday() # other hald of a date
#	- date() # just a date
#	- time() # just a time

#	- custom value parser:
#		Interface ValueParser{T}:
#			must have a metavar keyword arg
#			a parse function String -> ParseResult{T}
#			a format function T -> String


# modifying combinators: Transform existing Parsers adding additional behaviour on top of the core one
#	OK optional()
#	OK default()
#	OK multiple(min, max) (match multiple times, collect into an array.)
#	X map() # probably impossible to make typstable until we have something like TypedCallables
#	-

# construct combinators: combine different parsers into new ones
# 	OK object(), combines multiple named parsers into a single parser that produces a single object. Does not preserve order.
#	OK sequence(), combines parsers to produce tuple of results. preserves order of the final result, but not necessarily the parsing order.
#	OK or(), mutually exclusive alternatives
#   OK(TEST?) combine(), takes two parsers and generate a new single parser combining both
#	OK(TEST?) concat(), appends tuple parsers
#	- longest-match(), tries all parses and selects the one with the longest match.
#	- group(), documentation only combinator, adds a group label to parsers inside. Ensure to make it work also for groups of options!


# - Usage Mechanism
# - Automatic Help and pretty printing.
# - Suggestions Mechanism
# - Shell completions

# API Changes TODO/IDEAS
# - shorten names: object -> obj
# OK make optional boolean flags the default `flag` behaviour.
# OK rename required flag to `gate`
# - rename multiple to 'many'
# NO instead of combine and concat, use a single merge function? even possible?

export
    @?,
    @constant,
    arg,
    argparse,
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
    tryargparse,
    sequence,
    u16,
    u32,
    u64,
    u8,
    uuid

include("utils.jl")
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
    tryargparse(parser, argv)

Lower-level parsing entrypoint.

Returns a result object containing either the parsed value or a structured parse failure.
Unlike [`argparse`](@ref), this function does not throw on parse failures.
"""
function tryargparse(pp::Parser{T, S}, args::Vector{String})::ParseResult{T} where {T, S}

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
    argparse(parser, argv)

High-level parsing entrypoint.

This function currently has a build-time split:

- in normal Julia runtime usage, it returns the parsed value and throws
  [`ParseException`](@ref) on failure
- when compiled while `Base.generating_output()` is true, it renders the error
  to `stderr` and returns `nothing` on failure instead of throwing

If you need stable non-throwing behavior across environments, use
[`tryargparse`](@ref) instead.
"""
@static if Base.generating_output(false)

    function argparse(pp::Parser{T}, args::Vector{String})::Union{T, Nothing} where {T}
        mayberes = tryargparse(pp, args)::ParseResult{T}

        if is_error(mayberes)
            errmsg = sprint(showerror, ParseException(unwrap_error(mayberes)))
            print(Core.stderr, "Error: ")
            println(Core.stderr, errmsg)
            return nothing
        end

        return unwrap(mayberes)
    end
else
    function argparse(pp::Parser{T}, args::Vector{String})::T where {T}
        mayberes = tryargparse(pp, args)::ParseResult{T}

        if is_error(mayberes)
            throw(ParseException(unwrap_error(mayberes)))
        end

        return unwrap(mayberes)
    end
end



end # module OptParse
