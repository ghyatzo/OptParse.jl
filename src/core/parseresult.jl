"""
    Consumed <: AbstractVector{String}

A cheap, type-stable view of consumed CLI tokens.
Stores a reference to the original `buffer::Vector{String}` plus a `range`
into that buffer. Downstream code can index/iterate it like a vector of strings.

Materialize only when needed via `collect(consumed)` or `Tuple(consumed)`.
"""
struct Consumed <: AbstractVector{String}
    buffer::Vector{String}
    ranges::Vector{UnitRange{Int}}
end

Base.eltype(::Type{Consumed}) = String
Base.IndexStyle(::Type{Consumed}) = IndexLinear()
Base.size(c::Consumed) = (sum(length, c.ranges),)
Base.length(c::Consumed) = sum(length, c.ranges)

Base.getindex(c::Consumed, i::Int) = begin

    breaks = cumsum(length.(c.ranges))

    nextbreak = findfirst(>=(i), breaks)

    isnothing(nextbreak) && throw(BoundsError(c, i))

    pad = nextbreak == 1 ? 0 : breaks[nextbreak - 1]

    return c.buffer[c.ranges[nextbreak][i - pad]]
end

Base.iterate(c::Consumed, st::Int = 1) =
    st > length(c) ? nothing : (c[st], st + 1)

"""
    consumed_empty(buffer, pos)

Construct an empty consumption at position `pos` (range `pos:pos-1`).
"""
@inline consumed_empty(ctx; pos = ℒ_pos(ctx)) = Consumed(ctx_buffer(ctx), [pos:(pos - 1)])

# Optional convenience materializers (allocate on demand)
@inline as_vector(c::Consumed) = collect(c)
@inline as_tuple(c::Consumed) = Tuple(collect(c))


function _normalize_ranges(ranges::Vector{UnitRange{Int}})
    isempty(ranges) && return ranges
    rs = sort(ranges; by = r -> (first(r), last(r)))

    out = UnitRange{Int}[]
    cur = rs[1]
    for r in rs[2:end]
        if first(r) <= last(cur) + 1
            cur = first(cur):max(last(cur), last(r))
        else
            push!(out, cur)
            cur = r
        end
    end
    push!(out, cur)
    return out
end

"""
    merge(consumed::Vector{Consumed})

merges all the consumed into a single Consumed object. The buffer of each consumed can only increase.
In particular, it only changes when boundled options "-abc" are expanded into "-a" "-b" "-c".
all the ranges in each consumed object are relative to its buffer. what must happen is that those ranges must be
modified accordingly to the most expanded buffer (longest).
"""
function merge(consumed::Vector{Consumed})
    isempty(consumed) && error("merge(consumed): input vector is empty")

    buf = consumed[1].buffer
    @inbounds for c in consumed
        c.buffer === buf || error("merge(consumed): buffers differ; expected normalization to ensure a shared buffer")
    end

    all = UnitRange{Int}[]
    for c in consumed
        append!(all, c.ranges)
    end

    return Consumed(buf, _normalize_ranges(all))
end


#-----------------------------------------
#   Results / Errors
#--------------------------------------------


struct InnerParseSuccess{S}
    consumed::Consumed
    next::Context{S}
    counts_as_match::Bool
end

struct InnerParseFailure
    consumed::Int
    error::ParseError
end


const InnerParseResult{S} = Result{InnerParseSuccess{S}, InnerParseFailure}


const ℒ_nextctx = @o _.next
const ℒ_matchcounts = @o _.counts_as_match
const ℒ_consumed = @o _.consumed

const ℒ_ranges = (@o _.ranges) ∘ ℒ_consumed
const ℒ_error = @o _.error
const ℒ_nextstate = ℒ_state ∘ ℒ_nextctx

res_consumed(s::InnerParseSuccess) = ℒ_consumed(s)
res_num_consumed(f::InnerParseFailure) = ℒ_consumed(f)
res_num_consumed(s::InnerParseSuccess) = length(ℒ_consumed(s))
res_num_consumed(r::InnerParseResult) =
    is_error(r) ? res_num_consumed(unwrap_error(r)) : res_num_consumed(unwrap(r))

res_nextctx(s::InnerParseSuccess) = ℒ_nextctx(s)
res_matchcounts(s::InnerParseSuccess) = ℒ_matchcounts(s)

res_error(f::InnerParseFailure) = ℒ_error(f)
res_error(r::InnerParseResult) = res_error(unwrap_error(r))


@inline function innerOk(ctx::Context{S}, n::Int; nextctx::Context{S} = consume(ctx, n), counts_as_match = true)::InnerParseResult{S} where {S}
    p = ctx_pos(ctx)
    consumed = Consumed(ctx_buffer(ctx), [p:(p + n - 1)])
    return Ok(InnerParseSuccess{S}(consumed, nextctx, counts_as_match))
end

@inline function innerOk(next::Context{S}, cons::Consumed, counts_as_match = true)::InnerParseResult{S} where {S}
    return Ok(InnerParseSuccess{S}(cons, next, counts_as_match))
end

@inline function innerErr(ctx::Context{S}, e::ParseError; consumed::Int = 0)::InnerParseResult{S} where {S}
    return Err(InnerParseFailure(consumed, e))
end

@inline function innerErr(ctx::Context{S}, perr::InnerParseFailure)::InnerParseResult{S} where {S}
    return Err(InnerParseFailure(ℒ_consumed(perr), ℒ_error(perr)))
end

@inline function innerErr(ctx::Context{S}, res::InnerParseResult)::InnerParseResult{S} where {S}
    return innerErr(ctx, unwrap_error(res))
end


const ParseResult{T} = Result{T, ParseError}

@inline function typedOk(::Type{T}, value::V)::ParseResult{T} where {T, V <: T}
    # return ParseResult{T}(ErrorTypes.Ok{T}(ErrorTypes.unsafe, convert(T, value)))
    return Ok{T}(convert(T, value))
end

@inline function typedErr(::Type{T}, err::ParseError)::ParseResult{T} where {T}
    # return ParseResult{T}(ErrorTypes.Err{ParseError}(ErrorTypes.unsafe, err))
    return Err(err)
end

@inline typedOk(x) = Ok(x)
@inline typedErr(x) = Err(x)

error_with_trace(perr::ParseError, phase::ErrorPhase, domain::ErrorDomain, subject::String) = let
    errsite = ErrorSite(phase, domain, subject)
    push!(perr.trace, errsite)
    return perr
end

error_with_trace(err::ParseResult, phase::ErrorPhase, domain::ErrorDomain, subject::String) =
    error_with_trace(unwrap_error(err), phase, domain, subject)

error_with_trace(err::InnerParseResult, phase::ErrorPhase, domain::ErrorDomain, subject::String) =
    error_with_trace(res_error(err), phase, domain, subject)
