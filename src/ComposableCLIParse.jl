module ComposableCLIParse

using Accessors: @set, PropertyLens, insert, set
using WrappedUnions: @wrapped, @unionsplit
using ErrorTypes: @?, Err, Ok, Option, Result, is_error, none, some, unwrap, unwrap_error

# based on: https://optique.dev/concepts

# primitive parsers: building blocks of command line interfaces
#	- constant()
#	- option()
#	- flag()
#	- argument()
#	- command()
#	- parsers priority: command > argument > option > flag > constant


# value parsers: specialized components that convert raw string into desired outputs
#	- string(pattern)
#	- integer(min, max, type)
#	- float(min, max, allowInfinity, allowNan)
#	- choice([list of choices], caseinsensitive)
#	- uri()
#	- uuid()
#	- path()
#	- instant() # moment in time
#	- duration()
#	- zone-datetime()
#	- date()
#	- time()
#	- datetime()
#	- yearmonth()
#	- monthday()
#	- timezone()
#	- custom value parser:
#		Interface ValueParser{T}:
#			must have a metavar keyword arg
#			a parse function String -> ParseResult{T}
#			a format function T -> String


# modifying combinators: Transform existing Parsers adding additional behaviour on top of the core one
#	- optional()
#	- withDefault()
#	- map()
#	- multiple(min, max) (match multiple times, collect into an array.)
#	-

# construct combinators: combine different parsers into new ones
# 	- object(), combines multiple named parsers into a single parser that produces a single object
#	- tuple(), combines parsers to produce tuple of results. preserves order.
#	- or(), mutually exclusive alternatives
#	- merge(), takes two parsers and generate a new single parser combining both
#	- concat(), appends tuple parsers
#	- longest-match(), tries all parses and selects the one with the longest match.
#	- group(), documentation only combinator, adds a group label to parsers inside.

export argparse,
    # primitives
    constant,
    flag,
    option,

    # valueparsers
    str,
    choice,
    integer,

    # constructors
    object,

    # modifier
    optional,
    withDefault


include("parser.jl")
include("valueparsers/valueparsers.jl")
include("primitives/primitives.jl")
include("constructors/object.jl")
include("modifiers/modifiers.jl")

@wrapped struct Parser{T, S, p, P}
    union::Union{
        ArgFlag{T, S, p, P},
        ArgOption{T, S, p, P},
        ArgConstant{T, S, p, P},
        Object{T, S, p, P},
        ModOptional{T, S, p, P},
        ModWithDefault{T, S, p, P},
    }
end

parser(x::ArgFlag{T, S, p, P}) where {T, S, p, P} = Parser{T, S, p, P}(x)
parser(x::ArgOption{T, S, p, P}) where {T, S, p, P} = Parser{T, S, p, P}(x)
parser(x::ArgConstant{T, S, p, P}) where {T, S, p, P} = Parser{T, S, p, P}(x)
parser(x::Object{T, S, p, P}) where {T, S, p, P} = Parser{T, S, p, P}(x)
parser(x::ModOptional{T, S, p, P}) where {T, S, p, P} = Parser{T, S, p, P}(x)
parser(x::ModWithDefault{T, S, p, P}) where {T, S, p, P} = Parser{T, S, p, P}(x)

(priority(::Type{Parser{T, S, p, P}})::Int) where {T, S, p, P} = p
priority(o::Parser) = priority(typeof(o))

tval(::Type{Parser{T, S, p, P}}) where {T, S, p, P} = T
tstate(::Type{Parser{T, S, p, P}}) where {T, S, p, P} = S

Base.getproperty(p::Parser, f::Symbol) = @unionsplit Base.getproperty(p, f)
parse(p::Parser, ctx::Context) = @unionsplit parse(p, ctx)
complete(p::Parser, st) = @unionsplit complete(p, st)

# primitives
option(names::Vector{String}, valparser::ValueParser{T}; kw...) where {T} = parser(ArgOption(names, valparser; kw...))
flag(names::Vector{String}; kw...) = parser(ArgFlag(names; kw...))
constant(val) = parser(ArgConstant(val))

# constructors
object(obj::NamedTuple) = parser(_object(obj))
object(objlabel, obj::NamedTuple) = parser(_object(obj; label = objlabel))

# modifiers
optional(p::Parser) = parser(ModOptional(p))
withDefault(p::Parser{T}, default::T) where {T} = parser(ModWithDefault(p, default))


#####
# entry point
function argparse(pp::Parser{T, S, p}, args::Vector{String})::Result{T, String} where {T, S, p}

    ctx = Context(args, pp.initialState)

    while true
        mayberesult::ParseResult{S, String} = parse(pp, ctx)
        #=
			There is currently an issue. We need a mechanism to allow bypassing this check
			To allow for potential "fixable" errors (think optional) to pass through to the
			complete function. At first we simply updated the state, which works for single state
			parsers, but fails completely for multistate ones
		=#
        #=
			This is correct, no need to bypass anything. The error was that the optional parser
			was returning its child parse error as an error, while an optional parser
			should alway return a success with an error state, which can be picked up in the complete function
			but doesn't count as a proper Parseerror
		=#
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

    return endResult = complete(pp, ctx.state)
end

macro comment(_...) end

@comment begin
    using ComposableCLIParse
    args = ["--host", "me", "--verbose"]

    opt = option(["--host"], str(; metavar = "HOST"))
    flg = flag(["--verbose"])

    cst = constant(10)

    obj = object(
        "test", (
            cst = cst,
            option = opt,
            flag = flg,
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
