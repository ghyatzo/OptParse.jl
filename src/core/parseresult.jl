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

merges all the consumed into a single Consumed record. The buffer of each consumed can only increase.
In particular, it only changes when boundled options "-abc" are expanded into "-a" "-b" "-c".
all the ranges in each consumed record are relative to its buffer. what must happen is that those ranges must be
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


function consume(ctx, n)
    p = ctx_pos(ctx)
    return ctx_consume(ctx, n), Consumed(ctx_buffer(ctx), [p:(p + n - 1)])
end

#-----------------------------------------
#   Results / Errors
#--------------------------------------------


struct InnerParseSuccess{S}
    consumed::Consumed
    next::Context{S}
    counts_as_match::Bool
end

function Base.convert(::InnerParseSuccess{S}, inner::InnerParseSuccess{S2}) where {S, S2 <: S}
    InnerParseSuccess(
        ℒ_consumed(inner),
        widen_state(S, ℒ_nextctx(inner)),
        ℒ_matchcounts(inner)
    )
end

struct InnerParseFailure{E}
    consumed::Int
    error::E
end

InnerParseFailure{E}(x::InnerParseFailure{E2}) where {E, E2 <: E} = InnerParseFailure{E}(x.consumed, x.error)

const InnerParseResult{S, E} = Result{InnerParseSuccess{S}, InnerParseFailure{E}}


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


# ---- InnerParseResult widening constructors ----
# These accept ResultConstructors from innerOk/innerErr and widen type params.
# Used by the untyped innerOk/innerErr helpers (concrete types only).

function InnerParseResult{S, E}(x::ErrorTypes.ResultConstructor{InnerParseSuccess{S2}, Ok}) where {S, E, S2 <: S}
    inner = x.x
    return Result{InnerParseSuccess{S}, InnerParseFailure{E}}(typedOk(InnerParseSuccess{S},
        InnerParseSuccess(
            ℒ_consumed(inner),
            widen_state(S, ℒ_nextctx(inner)),
            ℒ_matchcounts(inner)
        )
    ))
end

function InnerParseResult{S, E}(x::ErrorTypes.ResultConstructor{InnerParseFailure{E2}, <:Err}) where {S, E, E2 <: E}
    inner = x.x
    return Result{InnerParseSuccess{S}, InnerParseFailure{E}}(
        typedErr(InnerParseFailure{E}, InnerParseFailure{E}(ℒ_consumed(inner), ℒ_error(inner))
    ))
end

# Trim-safe widening from a child InnerParseResult with narrower S2/E2 to wider S/E.
function InnerParseResult{S, E}(res::Result{InnerParseSuccess{S2}, InnerParseFailure{E2}}) where {S, E, S2 <: S, E2 <: E}
    inner = res.x
    if inner isa Err
        child_fail = inner.x
        return Result{InnerParseSuccess{S}, InnerParseFailure{E}}(
            typedErr(InnerParseFailure{E}, InnerParseFailure{E}(child_fail.consumed, child_fail.error))        )
    else
        child_ok = inner.x
        return Result{InnerParseSuccess{S}, InnerParseFailure{E}}(
            typedOk(InnerParseSuccess{S},
                InnerParseSuccess(child_ok.consumed, widen_state(S, child_ok.next), child_ok.counts_as_match))
        )
    end
end

# ---- InnerParseResult helpers ----

# Success: produces ResultConstructor → widened by constructor above
function innerOk(nextctx::Context, cons::Consumed; counts_as_match = true)
    return Ok(InnerParseSuccess(cons, nextctx, counts_as_match))
end

function innerOk(nextctx::Context, n; counts_as_match = true)
    return innerOk(consume(nextctx, n)...; counts_as_match)
end

# Failure from concrete error: produces ResultConstructor → widened by constructor above
function innerErr(e::AbstractParseError; consumed = 0)
    return Err(InnerParseFailure(consumed, e))
end

# Failure by widening child result: typed, produces Err{InnerParseFailure{E}} directly.
# Use this when E is a union or when the child result's error type needs widening.
function innerErr(::Type{E}, res::InnerParseResult) where {E}
    @assert is_error(res)
    child_err = unwrap_error(res)
    return typedErr(InnerParseFailure{E}, InnerParseFailure{E}(child_err.consumed, child_err.error))
end

# ---- ParseResult helpers ----

const ParseResult{T, E} = Result{T, E}

# Typed Ok/Err construction — bypasses ResultConstructor entirely.
# Use these when T or E is a union type (trimmer-safe).
typedOk(::Type{T}, value) where {T} = Ok{T}(ErrorTypes.unsafe, value)
typedErr(::Type{E}, error) where {E} = Err{E}(ErrorTypes.unsafe, error)
