
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

Reads go through the accessor functions (`buffer`, `pos`, `state`, `usage`,
`options_terminated`, `state_t`). Type-preserving updates go through the
`with_*`/`advance` helpers. Retagging updates (a change of the state type
parameter `S`) go through the checkpoint helpers (`with_state`, `restate`,
`widen_state`, `widen_restate`), which must rebuild the struct.
"""
@kwdef struct Context{S}
    buffer::Vector{String}
    pos::Int = 1
    state::S
    usage::UsageNode = UsageNode()
    optionsTerminated::Bool = false
end

# reads
buffer(ctx::Context) = ctx.buffer
pos(ctx::Context) = ctx.pos
state(ctx::Context) = ctx.state
usage(ctx::Context) = ctx.usage
options_terminated(ctx::Context) = ctx.optionsTerminated
state_t(::Context{S}) where {S} = S

# type-preserving updates
@inline with_options_terminated(ctx::Context, flag::Bool) = @set ctx.optionsTerminated = flag
@inline with_buffer(ctx::Context, buf::Vector{String}) = @set ctx.buffer = buf
@inline with_pos(ctx::Context, pos::Int) = @set ctx.pos = pos

# -----------------------------------------------------------------------------
# Centralized "checkpoints" and state retagging
# -----------------------------------------------------------------------------

"""
    with_state(ctx, s::S) where S -> Context{S}

Creates a new context with the same buffer/options flag but **forces** the
context's state parameter to be `S`.

"""
@inline function with_state(ctx::Context, s::S) where {S}
    return Context{S}(
        ctx.buffer,
        ctx.pos,
        s,
        ctx.usage,
        ctx.optionsTerminated
    )
end

"""
    restate(ctx, s::S) where S -> Context{S}

Creates a new context with the same buffer/options flag but **forces** the
context's state parameter to be `S`.
The difference with with_state is purely semantic. This is better used to
indicate that we're simply wrapping the state of the context, instead of "creating a new context."

"""
@inline restate(ctx::Context, s::S) where {S} = with_state(ctx, s)


"""
    widen_state(::Type{B}, ctx::Context{T}) where {B, T <: B} -> Context{B}

Returns a context whose state parameter is widened to `B` where B must be a supertype of T.
This is useful when you need to "upgrade" `Context{T}` to `Context{Union{T,B}}` for example.
in a type-stable way (as long as `B` is a compile-time type known value).
"""
@inline function widen_state(::Type{B}, ctx::Context{T}) where {B, T <: B}
    U = promote_type(T, B)
    return Context{U}(
        ctx.buffer,
        ctx.pos,
        convert(U, ctx.state),
        ctx.usage,
        ctx.optionsTerminated
    )
end

"""
    widen_restate(::Type{B}, ctx::Context{T}, newstate) where {B, T <: B} -> Context{B}

Utility function that combines a new state while also widening it
"""
@inline function widen_restate(::Type{B}, ctx::Context, s) where {B}
    return Context{B}(
        ctx.buffer,
        ctx.pos,
        convert(B, s),
        ctx.usage,
        ctx.optionsTerminated
    )
end


# -----------------------------------------------------------------------------
# Buffer helpers
# -----------------------------------------------------------------------------


@inline hasmore(ctx::Context) = length(ctx.buffer) - (ctx.pos - 1) > 0
@inline haslessthan(n::Int, ctx::Context) = length(ctx.buffer) - (ctx.pos - 1) < n
@inline hasnone(ctx::Context) = !hasmore(ctx)

@inline peek(ctx::Context, n::Int = 1) = ctx.buffer[ctx.pos + n - 1]
@inline peekn(ctx::Context, n::Int = 1) = ctx.buffer[ctx.pos:ctx.pos + n - 1]

@inline remaining(ctx::Context) = ctx.buffer[ctx.pos:end]
@inline remaining_len(ctx::Context) = length(ctx.buffer) - (ctx.pos - 1)

"""
    advance(ctx, n)

Type-preserving update: move the cursor `n` tokens forward.
"""
@inline advance(ctx::Context, n::Int) = @set ctx.pos = ctx.pos + n
