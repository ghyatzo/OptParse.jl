module ComposableCLIParse

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
#	OK option()
#	OK flag()
#   OK argument()
#	OK command()
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
#	NOTPLANNED map() # probably impossible to make typstable until we don't have ValuedFunctions
#	-

# construct combinators: combine different parsers into new ones
# 	OK object(), combines multiple named parsers into a single parser that produces a single object. Does not preserve order.
#	OK tuple(), combines parsers to produce tuple of results. preserves order of the final result, but not necessarily the parsing order.
#	OK or(), mutually exclusive alternatives
#	- merge(), takes two parsers and generate a new single parser combining both
#	- concat(), appends tuple parsers
#	- longest-match(), tries all parses and selects the one with the longest match.
#	- group(), documentation only combinator, adds a group label to parsers inside.

export argparse,
    # primitives
    @constant,
    flag,
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
include("parser.jl")
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
        ModMultiple{T, S, p, P}
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


# primitives
option(names::Tuple{Vararg{String}}, valparser::ValueParser{T}; kw...) where {T} =
    _parser(ArgOption(Tuple(names), valparser; kw...))
option(opt1::String, valparser::ValueParser{T}; kw...) where {T} =
    _parser(ArgOption((opt1,), valparser; kw...))
option(opt1::String, opt2::String, valparser::ValueParser{T}; kw...) where {T} =
    _parser(ArgOption((opt1, opt2), valparser; kw...))
option(opt1::String, opt2::String, opt3::String, valparser::ValueParser{T}; kw...) where {T} =
    _parser(ArgOption((opt1, opt2, opt3), valparser; kw...))

flag(names...; kw...) = _parser(ArgFlag(names; kw...))

macro constant(val)
    return :(_parser(ArgConstant($val)))
end

argument(valparser::ValueParser{T}; kw...) where {T} = _parser(ArgArgument(valparser; kw...))

command(name::String, p::Parser; kw...) = _parser(ArgCommand(name, p))



# constructors
object(obj::NamedTuple) = _parser(_object(obj))
object(objlabel, obj::NamedTuple) = _parser(_object(obj; label = objlabel))

or(parsers...) = _parser(ConstrOr(parsers))

tup(parsers...; kw...) = _parser(ConstrTuple(parsers; kw...))
tup(label::String, parsers...; kw...) = _parser(ConstrTuple(parsers; label, kw...))



# modifiers
optional(p::Parser) = _parser(ModOptional(p))


withDefault(p::Parser, default) = _parser(ModWithDefault(p, default))
withDefault(default) = (p::Parser) -> _parser(ModWithDefault(p, default))

multiple(p::Parser; kw...) = _parser(ModMultiple(p; kw...))



#####
# entry point
function argparse(pp::Parser{T, S, p}, args::Vector{String})::Result{T, String} where {T, S, p}

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

    return endResult = @unionsplit complete(pp, ctx.state)
end

macro comment(_...) end

@comment begin
    using ComposableCLIParse
    args = ["--host", "me", "--verbose", "--test"]

    opt = option(["--host"], str(; metavar = "HOST"))
    flg = flag(["--verbose"])
    flg2 = flag(["--test"])

    cst = constant(10)

    obj = object(
        "test", (
            # cst = cst,
            option = opt,
            flag = flg,
            flag2 = flg2,
        )
    )

    opt_opt = optional(opt)
    def_flg = withDefault(flg, false)

    obj2 = object(
        "test mod", (
            option = opt_opt,
            flag = def_flg,
        )
    )

    arg = argument(str(; metavar = "TEST"))


    using JET
    @report_opt argparse(opt, ["--host", "me"])
    @report_opt argparse(flg, ["--verbose"])
    @report_opt argparse(obj, args)

    @report_opt argparse(opt_opt, String[])
    @report_opt argparse(def_flg, String[])

    @report_opt argparse(obj2, String[])

    @btime ComposableCLIParse._sort_obj(nt) setup = begin
        opt = option(["--host"], stringval(; metavar = "HOST"))
        flg = flag(["--verbose"])

        nt = (option = opt, flag = flg)
    end
end

end # module ComposableCLIParse
