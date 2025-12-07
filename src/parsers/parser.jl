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

function withDefault end

withDefault(p::Parser, default) = _parser(ModWithDefault(p, default))
withDefault(default) = (p::Parser) -> _parser(ModWithDefault(p, default))

## Optional
function optional end

optional(p::Parser) = withDefault(p, nothing)
# optional(p::Parser) = _parser(ModOptional(p))

## Multiple
function multiple end

multiple(p::Parser; kw...) = _parser(ModMultiple(p; kw...))


# primitives

## Option
function option end

option(names::Tuple{Vararg{String}}, valparser::ValueParser{T}; kw...) where {T} =
    _parser(ArgOption(Tuple(names), valparser; kw...))
option(opt1::String, valparser::ValueParser{T}; kw...) where {T} =
    _parser(ArgOption((opt1,), valparser; kw...))
option(opt1::String, opt2::String, valparser::ValueParser{T}; kw...) where {T} =
    _parser(ArgOption((opt1, opt2), valparser; kw...))
option(opt1::String, opt2::String, opt3::String, valparser::ValueParser{T}; kw...) where {T} =
    _parser(ArgOption((opt1, opt2, opt3), valparser; kw...))

## Flag
function flag end
flag(names...; kw...) = _parser(ArgFlag(names; kw...))

## OptFlag
function optflag end
optflag(names...; kw...) = withDefault(flag(names...; kw...), false)

## Constant
macro constant(val)
    return :(_parser(ArgConstant($val)))
end

## Argument
function argument end
argument(valparser::ValueParser{T}; kw...) where {T} = _parser(ArgArgument(valparser; kw...))

## command
function command end

command(name::String, p::Parser; kw...) = _parser(ArgCommand(name, p; kw...))


# constructors

## Object
function object end

object(obj::NamedTuple) = _parser(_object(obj))
object(objlabel, obj::NamedTuple) = _parser(_object(obj; label = objlabel))

## Objmerge
function objmerge end
objmerge(objs...; label = "") = _parser(_object(_merge(objs); label))

## Or
function or end
or(parsers...) = _parser(ConstrOr(parsers))

## Tup
function tup end

tup(parsers...; kw...) = _parser(ConstrTuple(parsers; kw...))
tup(label::String, parsers...; kw...) = _parser(ConstrTuple(parsers; label, kw...))

## Concat
function concat end
concat(tups...; label = "", allowDuplicates = false) = _parser(ConstrTuple(_concat(tups); label, allowDuplicates))
