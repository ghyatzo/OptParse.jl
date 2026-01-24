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

    pad = nextbreak == 1 ? 0 : breaks[nextbreak-1]

    return c.buffer[c.ranges[nextbreak][i-pad]]
end

Base.iterate(c::Consumed, st::Int=1) =
    st > length(c) ? nothing : (c[st], st + 1)

"""
    consumed_empty(buffer, pos)

Construct an empty consumption at position `pos` (range `pos:pos-1`).
"""
@inline consumed_empty(ctx; pos=ℒ_pos(ctx)) = Consumed(ℒ_buffer(ctx), [pos:(pos-1)])

# Optional convenience materializers (allocate on demand)
@inline as_vector(c::Consumed) = collect(c)
@inline as_tuple(c::Consumed) = Tuple(collect(c))


struct ParseSuccess{S}
    consumed::Consumed
    next::Context{S}
end

struct ParseFailure{E}
    consumed::Int
    error::E
end

const ParseResult{S, E} = Result{ParseSuccess{S}, ParseFailure{E}}


const ℒ_nextctx = @optic _.next
const ℒ_consumed = @optic _.consumed
const ℒ_nconsumed = @optic _.consumed

const ℒ_ranges = (@optic _.ranges) ∘ ℒ_consumed
const ℒ_error = @optic _.error
const ℒ_nextstate = ℒ_state ∘ ℒ_nextctx


@inline parseok(ctx::Context{S}, n::Int; nextctx::Context{S}=consume(ctx, n)) where {S} = let
    p = ℒ_pos(ctx)
    consumed = Consumed(ℒ_buffer(ctx), [p:p+n-1])
    return Ok(ParseSuccess{S}(consumed, nextctx))
end

@inline parseok(next::Context{S}, cons::Consumed) where {S} =
    Ok(ParseSuccess{S}(cons, next))


@inline parseerr(_ctx::Context, e; consumed::Int=0) =
    Err(ParseFailure(consumed, e))

@inline parseerr(perr::ParseFailure) =
    Err(ParseFailure(perr.consumed, perr.error))


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
