
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
    path::Vector{Breadcrumb} = Breadcrumb[]
end

# Note: the ℒ is `\\scrL<TAB>`
const ℒ_buffer  = @o _.buffer
const ℒ_pos     = @o _.pos
const ℒ_state   = @o _.state
const ℒ_optterm = @o _.optionsTerminated
const ℒ_path    = @o _.path

# -----------------------------------------------------------------------------
# Centralized "checkpoints" and state retagging
# -----------------------------------------------------------------------------

"""
    ctx_with_state(ctx, s::S) where S -> Context{S}

Creates a new context with the same buffer/options flag but **forces** the
context's state parameter to be `S`. This is the canonical "inference checkpoint".

"""
@inline function ctx_with_state(ctx::Context, s::S) where {S}
    return Context{S}(
        ctx.buffer,
        ctx.pos,
        s,
        ctx.optionsTerminated,
        ctx.path
    )
end

"""
    ctx_restate(ctx, s::S) where S -> Context{S}

Creates a new context with the same buffer/options flag but **forces** the
context's state parameter to be `S`. This is the canonical "inference checkpoint".
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
        ctx.buffer,
        ctx.pos,
        convert(U, ctx.state),
        ctx.optionsTerminated,
        ctx.path
    )
end

"""
    widen_restate(::Type{B}, ctx::Context{T}, newstate) where {B, T <: B} -> Context{B}

Utility function that combines a new state while also widening it
"""
@inline function widen_restate(::Type{B}, ctx::Context, s::S) where {B, S <: B}
    U = promote_type(S, B)
    return Context{U}(
        ctx.buffer,
        ctx.pos,
        convert(U, s),
        ctx.optionsTerminated,
        ctx.path
    )
end

# -----------------------------------------------------------------------------
# Convenience setters / transformers
# -----------------------------------------------------------------------------


@inline ctx_with_buffer(ctx::Context, buf::Vector{String}) = set(ctx, ℒ_buffer, buf)
@inline ctx_with_options_terminated(ctx::Context, flag::Bool) = set(ctx, ℒ_optterm, flag)
@inline ctx_with_path(ctx::Context, path::Vector{Breadcrumb}) = set(ctx, ℒ_path, path)
@inline ctx_push_breadcrumb(ctx::Context, bc::Breadcrumb) = let
    newpath = Breadcrumb[b for b in ctx.path]
    push!(newpath, bc)
    set(ctx, ℒ_path, newpath)
end
@inline ctx_with_pos(ctx::Context, pos::Int) = set(ctx, ℒ_pos, pos)

"""
    ctx_map_state(f, ctx)

Applies `f` to the current state and returns a new context.
Serves as a convenient place to hide state transformations.

Note: inference usually succeeds if `f` is type-stable and concrete at call site.
If hitting inference issues, prefer `ctx_with_state(ctx, f(state))` explicitly.
"""
@inline function ctx_map_state(f, ctx::Context)
    s2 = f(ctx.state)
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


@inline ctx_hasmore(ctx::Context) = length(ctx.buffer) - (ctx.pos - 1) > 0
@inline ctx_haslessthan(n::Int, ctx::Context) = length(ctx.buffer) - (ctx.pos - 1) < n
@inline ctx_hasnone(ctx::Context) = !ctx_hasmore(ctx)

@inline ctx_peek(ctx::Context, n::Int=1) = ctx.buffer[ctx.pos+n-1]
@inline ctx_peekn(ctx::Context, n::Int=1) = ctx.buffer[ctx.pos:ctx.pos+n-1]

@inline ctx_remaining(ctx::Context) = ctx.buffer[ctx.pos:end]
@inline ctx_length(ctx::Context) = length(ctx.buffer) - (ctx.pos - 1)

@inline consume(ctx::Context, n::Int) = ctx_with_pos(ctx, ctx.pos+n)

