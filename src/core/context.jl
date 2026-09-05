

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
@kwdef struct Context{S}
    buffer::Vector{String}
    pos::Int = 1
    state::S
    usage::UsageNode = UsageNode()
    optionsTerminated::Bool = false
end

# Note: the ℒ is `\\scrL<TAB>`
const ℒ_buffer  = @o _.buffer
const ℒ_pos     = @o _.pos
const ℒ_state   = @o _.state
const ℒ_usage   = @o _.usage
const ℒ_optterm = @o _.optionsTerminated

ctx_buffer(ctx::Context) = ℒ_buffer(ctx)
ctx_pos(ctx::Context) = ℒ_pos(ctx)
ctx_state(ctx::Context) = ℒ_state(ctx)
ctx_usage(ctx::Context) = ℒ_usage(ctx)
ctx_optterm(ctx::Context) = ℒ_optterm(ctx)
ctx_tstate(::Context{S}) where {S} = S

@inline ctx_with_options_terminated(ctx::Context, flag::Bool) = set(ctx, ℒ_optterm, flag)
@inline ctx_with_buffer(ctx::Context, buf::Vector{String}) = set(ctx, ℒ_buffer, buf)
@inline ctx_with_pos(ctx::Context, pos::Int) = set(ctx, ℒ_pos, pos)
# -----------------------------------------------------------------------------
# Centralized "checkpoints" and state retagging
# -----------------------------------------------------------------------------

"""
    ctx_with_state(ctx, s::S) where S -> Context{S}

Creates a new context with the same buffer/options flag but **forces** the
context's state parameter to be `S`.

"""
@inline function ctx_with_state(ctx::Context, s::S) where {S}
    return Context{S}(
        ℒ_buffer(ctx),
        ℒ_pos(ctx),
        s,
        ℒ_usage(ctx),
        ℒ_optterm(ctx)
    )
end

"""
    ctx_restate(ctx, s::S) where S -> Context{S}

Creates a new context with the same buffer/options flag but **forces** the
context's state parameter to be `S`.
The difference with ctx_with_state is purely semantic. This is better used to
indicate that we're simply wrapping the state of the context, instead of "creating a new context."

"""
@inline ctx_restate(ctx::Context, s::S) where {S} = ctx_with_state(ctx, s)


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
        ℒ_usage(ctx),
        ℒ_optterm(ctx)
    )
end

"""
    widen_restate(::Type{B}, ctx::Context{T}, newstate) where {B, T <: B} -> Context{B}

Utility function that combines a new state while also widening it
"""
@inline function widen_restate(::Type{B}, ctx::Context, s) where {B}
    return Context{B}(
        ℒ_buffer(ctx),
        ℒ_pos(ctx),
        convert(B, s),
        ℒ_usage(ctx),
        ℒ_optterm(ctx)
    )
end


# -----------------------------------------------------------------------------
# Buffer helpers
# -----------------------------------------------------------------------------


@inline ctx_hasmore(ctx::Context) = length(ℒ_buffer(ctx)) - (ℒ_pos(ctx) - 1) > 0
@inline ctx_haslessthan(n::Int, ctx::Context) = length(ℒ_buffer(ctx)) - (ℒ_pos(ctx) - 1) < n
@inline ctx_hasnone(ctx::Context) = !ctx_hasmore(ctx)

@inline ctx_peek(ctx::Context, n::Int=1) = ℒ_buffer(ctx)[ℒ_pos(ctx)+n-1]
@inline ctx_peekn(ctx::Context, n::Int=1) = ℒ_buffer(ctx)[ℒ_pos(ctx):ℒ_pos(ctx)+n-1]

@inline ctx_remaining(ctx::Context) = ℒ_buffer(ctx)[ℒ_pos(ctx):end]
@inline ctx_length(ctx::Context) = length(ℒ_buffer(ctx)) - (ℒ_pos(ctx) - 1)

@inline ctx_consume(ctx::Context, n::Int) =
    set(ctx, ℒ_pos, ℒ_pos(ctx)+n)

