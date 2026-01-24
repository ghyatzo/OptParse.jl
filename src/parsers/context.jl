
# -----------------------------------------------------------------------------
# Context & state aliases
# -----------------------------------------------------------------------------

"""
    Context{S}

Parsing context carrying:
- `buffer`: contains all the arguments/tokens passed in to the program.
- `pos`: contains the position in the buffer. The current token.
- `state`: parser state accumulator.
- `optionsTerminated`: whether `--` or equivalent was encountered
"""
Base.@kwdef struct Context{S}
    buffer::Vector{String}
    pos::Int = 1
    state::S
    optionsTerminated::Bool = false
end

# -----------------------------------------------------------------------------
# Custom optics (define once; use everywhere)
# -----------------------------------------------------------------------------

"""
    ℒ_buffer, ℒ_pos, ℒ_state, ℒ_optterm

Stable optics for Context fields. Use these instead of `@optic _.field`
throughout the codebase to make refactors easier.

Note: the ℒ is `\\scrL<TAB>`
"""
const ℒ_buffer  = @optic _.buffer
const ℒ_pos     = @optic _.pos
const ℒ_state   = @optic _.state
const ℒ_optterm = @optic _.optionsTerminated

# -----------------------------------------------------------------------------
# Centralized "checkpoints" and state retagging
# -----------------------------------------------------------------------------

"""
    ctx_with_state(ctx, s::S) where S -> Context{S}

Creates a new context with the same buffer/options flag but **forces** the
context's state parameter to be `S`. This is the canonical "inference checkpoint".

"""
@inline function ctx_with_state(ctx::Context, s::S) where {S}
    return Context{S}(ℒ_buffer(ctx), ℒ_pos(ctx), s, ℒ_optterm(ctx))
end


"""
    widen_state(::Type{B}, ctx::Context{T}) where {B, T <: B} -> Context{B}

Returns a context whose state parameter is widened to `B` where B must be a supertype of T.
This is useful when you need to "upgrade" `Context{T}` to `Context{Union{T,B}}` for example.
in a type-stable way (as long as `B` is a compile-time type known value).
"""
@inline function widen_state(::Type{B}, ctx::Context{T}) where {B, T <: B}
    U = promote_type(T, B)
    return Context{U}(
        ℒ_buffer(ctx),
        ℒ_pos(ctx),
        convert(U, ℒ_state(ctx)),
        ℒ_optterm(ctx)
    )
end

# -----------------------------------------------------------------------------
# Convenience setters / transformers
# -----------------------------------------------------------------------------

"""
    ctx_with_options_terminated(ctx, flag::Bool)

Updates the optionsTerminated flag using optics.
"""
@inline ctx_with_options_terminated(ctx::Context, flag::Bool) =
    set(ctx, ℒ_optterm, flag)

"""
    ctx_map_state(f, ctx)

Applies `f` to the current state and returns a new context.
Serves as a convenient place to hide state transformations.

Note: inference usually succeeds if `f` is type-stable and concrete at call site.
If hitting inference issues, prefer `ctx_with_state(ctx, f(state))` explicitly.
"""
@inline function ctx_map_state(f, ctx::Context)
    s2 = f(ℒ_state(ctx))
    return ctx_with_state(ctx, s2)   # keeps the checkpoint centralized
end




# -----------------------------------------------------------------------------
# Buffer helpers
# -----------------------------------------------------------------------------

"""
    ctx_buffer(ctx) -> Vector{String}
    ctx_with_buffer(ctx, buf::Vector{String})

Small wrappers around buffer access.
"""


@inline ctx_with_buffer(ctx::Context, buf::Vector{String}) = set(ctx, ℒ_buffer, buf)

@inline ctx_hasmore(ctx::Context) = length(ℒ_buffer(ctx)) - (ℒ_pos(ctx) - 1) > 0
@inline ctx_haslessthan(n::Int, ctx::Context) = length(ℒ_buffer(ctx)) - (ℒ_pos(ctx) - 1) < n
@inline ctx_hasnone(ctx::Context) = !ctx_hasmore(ctx)

@inline ctx_peek(ctx::Context, n::Int=1) = ℒ_buffer(ctx)[ℒ_pos(ctx)+n-1]
@inline ctx_peekn(ctx::Context, n::Int=1) = ℒ_buffer(ctx)[ℒ_pos(ctx):ℒ_pos(ctx)+n-1]

@inline ctx_remaining(ctx::Context) = ℒ_buffer(ctx)[ℒ_pos(ctx):end]
@inline ctx_length(ctx::Context) = length(ℒ_buffer(ctx)) - (ℒ_pos(ctx) - 1)

@inline consume(ctx::Context, n::Int) =
    set(ctx, ℒ_pos, ℒ_pos(ctx)+n)


# -----------------------------------------------------------------------------
# Optional: Parse result types + constructors
# -----------------------------------------------------------------------------


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
@inline consumed_empty(buffer::Vector{String}, pos::Int) = Consumed(buffer, pos:(pos-1))

# Optional convenience materializers (allocate on demand)
@inline as_vector(c::Consumed) = collect(c)
@inline as_tuple(c::Consumed) = Tuple(collect(c))


# struct ParseSuccess{S}
#     consumed::Tuple{Vararg{String}} # keep your current representation for now
#     next::Context{S}
# end

# struct ParseFailure{E}
#     consumed::Int
#     error::E
# end

# const ParseResult{S, E} = Result{ParseSuccess{S}, ParseFailure{E}}

# @inline ParseOk(cons::Tuple{Vararg{String}}, next::Context{S}) where {S} = Ok(ParseSuccess{S}(cons, next))
# @inline ParseErr(consumed::Int, error) = Err(ParseFailure(consumed, error))


# function ok(ctx::Context{S}, n::Int; nextctx::Context{S}=consume(ctx, n)) where {S}
#     cons = ctx_peekn(ctx)
#     return ParseOk(cons, nextctx)
# end
