"""
    Consumed <: AbstractVector{String}

A cheap, type-stable view of consumed CLI tokens.
Stores a reference to the original `buffer::Vector{String}` plus a `range`
into that buffer. Downstream code can index/iterate it like a vector of strings.

Materialize only when needed via `collect(consumed)` or `Tuple(consumed)`.
"""
struct Consumed <: AbstractVector{String}
    buffer::Vector{String}
    range::UnitRange{Int}
end

Base.eltype(::Type{Consumed}) = String
Base.IndexStyle(::Type{Consumed}) = IndexLinear()
Base.size(c::Consumed) = (length(c.range),)
Base.length(c::Consumed) = length(c.range)

Base.getindex(c::Consumed, i::Int) = c.buffer[c.range[i]]

Base.iterate(c::Consumed, st::Int=first(c.range)) =
    st > last(c.range) ? nothing : (c.buffer[st], st + 1)

"""
    consumed_empty(buffer, pos)

Construct an empty consumption at position `pos` (range `pos:pos-1`).
"""
@inline consumed_empty(ctx; pos=ℒ_pos(ctx)) = Consumed(ℒ_buffer(ctx), pos:(pos-1))

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
const ℒ_error = @optic _.error
const ℒ_nextstate = ℒ_state ∘ ℒ_nextctx

@inline ok_restate(parseok::ParseSuccess, newctx::Context{S}) where {S} =
    set(parseok, ℒ_nextctx, newctx)

@inline err_rethrow(parseerr::ParseFailure) =
    Err(ParseFailure(ℒ_nconsumed(parseerr), ℒ_error(parseerr)))

# # TODO: the transformation to tuple is not trimmable
# @inline ParseOk(cons::Consumed, next::Context{S}) where {S} = Ok(ParseSuccess{S}(cons, next))
# @inline ParseErr(consumed, error) = Err(ParseFailure(consumed, error))

function ParseOk(ctx::Context{S}, n::Int; nextctx::Context{S}=consume(ctx, n)) where {S}
    p = ℒ_pos(ctx)
    consumed = Consumed(
        ℒ_buffer(ctx),
        p:p+n-1
    )
    return Ok(ParseSuccess{S}(consumed, nextctx))
end

function ParseErr(err::String, ctx::Context{S}; consumed::Int = 0) where {S}
    return Err(ParseFailure(consumed, err))
end
