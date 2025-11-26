abstract type AbstractParser{T, S, p, P} end

tval(::Type{<:AbstractParser{T}}) where {T} = T
tval(::AbstractParser{T}) where {T} = T

tstate(::Type{<:AbstractParser{T, S}}) where {T, S} = S
tstate(::AbstractParser{T, S}) where {T, S} = S

(priority(::Type{<:AbstractParser{T, S, _p}})::Int) where {T, S, _p} = _p
priority(::AbstractParser{T, S, _p}) where {T, S, _p} = _p

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

ParseOk(consumed, next::Context{S}) where {S} =
    Ok(ParseSuccess(consumed, next))
ParseErr(consumed, error) =
    Err(ParseFailure(consumed, error))
