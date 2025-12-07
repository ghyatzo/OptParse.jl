module CLIpper

using Accessors:
    IndexLens,
    insert,
    PropertyLens,
    set,
    @set

using WrappedUnions:
    @unionsplit,
    unwrap as unwrapunion, #=conflicts with the unwrap from ErrorTypes.jl=#
    WrappedUnions,
    @wrapped

using ErrorTypes:
    @?,
    base,
    Err,
    is_error,
    is_ok_and,
    none,
    Ok,
    Option,
    Result,
    some,
    unwrap,
    unwrap_error,
    @unwrap_or

using UUIDs:
    UUID,
    uuid_version

# based on: https://optique.dev/concepts

# primitive parsers: building blocks of command line interfaces
#	OK constant()
#	OK option() # Add support for -Lval style options
#	OK flag()
#   OK argument()
#	OK command() # add command aliases to commands "status" "st"
#   ? PassThrough()
#	- parsers priority: command > argument > option > flag > constant


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
#	OK withDefault()
#	OK multiple(min, max) (match multiple times, collect into an array.)
#	X map() # probably impossible to make typstable until we have something like TypedCallables
#	-

# construct combinators: combine different parsers into new ones
# 	OK object(), combines multiple named parsers into a single parser that produces a single object. Does not preserve order.
#	OK tuple(), combines parsers to produce tuple of results. preserves order of the final result, but not necessarily the parsing order.
#	OK or(), mutually exclusive alternatives
#   OK(TEST?) merge(), takes two parsers and generate a new single parser combining both
#	OK(TEST?) concat(), appends tuple parsers
#	- longest-match(), tries all parses and selects the one with the longest match.
#	- group(), documentation only combinator, adds a group label to parsers inside.
#   ? conditional(), check 0.7.1


# - Usage Mechanism
# - Automatic Help and pretty printing.
# - Suggestions Mechanism
# - Better Errors
# - Shell completions

export argparse,
    # primitives
    @constant,
    flag,
    optflag,
    option,
    argument,
    command,

    # valueparsers
    str,
    choice,
    integer,
    i8,
    i16,
    i32,
    i64,
    u8,
    u16,
    u32,
    u64,
    flt,
    flt32,
    flt64,
    uuid,

    # constructors
    object,
    or,
    tup,

    # modifier
    optional,
    withDefault,
    multiple

include("utils.jl")
include("parsers/parser.jl")


#####
# entry point
function argparse(pp::Parser{T, S}, args::Vector{String})::Result{T, String} where {T, S}

    ctx = Context{S}(args, pp.initialState, false)

    while true
        mayberesult::ParseResult{S, String} = @unionsplit parse(pp, ctx)

        if is_error(mayberesult)
            return Err(unwrap_error(mayberesult).error)
        end
        result = unwrap(mayberesult)

        previous_buffer = ctx.buffer
        ctx = result.next

        if (
                length(ctx.buffer) > 0
                    && length(ctx.buffer) == length(previous_buffer)
                    && ctx.buffer[1] === previous_buffer[1]
            )

            return Err("Unexpected option or argument: $(ctx.buffer[1]).")
        end

        length(ctx.buffer) > 0 || break
    end

    return @unionsplit complete(pp, ctx.state)
end

end # module CLIpper
