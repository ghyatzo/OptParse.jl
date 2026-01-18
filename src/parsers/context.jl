
# -----------------------------------------------------------------------------
# Context & state aliases
# -----------------------------------------------------------------------------

"""
    Context{S}

Parsing context carrying:
- `buffer`: remaining arguments/tokens (currently represented directly; cursor/span may come later)
- `state`: parser state accumulator
- `optionsTerminated`: whether `--` or equivalent was encountered
"""
Base.@kwdef struct Context{S}
    buffer::Vector{String}
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
"""
const ℒ_buffer  = @optic _.buffer
const ℒ_state   = @optic _.state
const ℒ_optterm = @optic _.optionsTerminated

# -----------------------------------------------------------------------------
# Centralized "checkpoints" and state retagging
# -----------------------------------------------------------------------------

"""
    ctx_with_state(ctx, s::S) where S -> Context{S}

Creates a new context with the same buffer/options flag but **forces** the
context's state parameter to be `S`. This is the canonical "inference checkpoint".

Use this instead of `Context{S}(...)` in parser code.
"""
@inline function ctx_with_state(ctx::Context, s::S) where {S}
    return Context{S}(ℒ_buffer(ctx), s, ℒ_optterm(ctx))
end

"""
    ctx_restate(ctx, newstate) -> Context{typeof(newstate)}

Retags the context to a new state type (e.g. `S` -> `MultipleState{S}`).

Use this when "upgrading" or switching accumulator types.
"""
@inline ctx_restate(ctx::Context, newstate) = ctx_with_state(ctx, newstate)

"""
    widen_state(::Type{B}, ctx::Context{T}) where {B, T <: B} -> Context{B}

Returns a context whose state parameter is widened to `B` where B must be a supertype of T.
This is useful when you need to "upgrade" `Context{T}` to `Context{Union{T,B}}` for example.
in a type-stable way (as long as `B` is a compile-time type).
"""
@inline function widen_state(::Type{B}, ctx::Context{T}) where {T,B}
    U = promote_type(T, B)
    return Context{U}(
        ℒ_buffer(ctx),
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
If you hit inference issues, prefer `ctx_with_state(ctx, f(state))` explicitly.
"""
@inline function ctx_map_state(f, ctx::Context)
    s2 = f(ℒ_state(ctx))
    return ctx_with_state(ctx, s2)   # keeps the checkpoint centralized
end




# -----------------------------------------------------------------------------
# Buffer helpers (still slice-based for now)
# -----------------------------------------------------------------------------

"""
    ctx_buffer(ctx) -> Vector{String}
    ctx_with_buffer(ctx, buf::Vector{String})

Small wrappers around buffer access. If you later move to cursor/span, you’ll
update these and the rest of the code can stay the same.
"""


@inline ctx_with_buffer(ctx::Context, buf::Vector{String}) = set(ctx, ℒ_buffer, buf)
@inline ctx_hasmore(ctx::Context) = length(ℒ_buffer(ctx)) > 0
@inline ctx_haslessthan(n::Int, ctx::Context) = length(ℒ_buffer(ctx)) < n
@inline ctx_hasnone(ctx::Context) = !ctx_hasmore(ctx)

@inline ctx_peek(ctx::Context, n::Int=1) = ℒ_buffer(ctx)[n]
@inline ctx_peekn(ctx::Context, n::Int=1) = ℒ_buffer(ctx)[1:n]

@inline consume(ctx::Context, n::Int) =
    set(ctx, ℒ_buffer, ℒ_buffer(ctx)[n+1:end])

@inline ctx_remaining(ctx::Context) = ℒ_buffer(ctx)
@inline ctx_length(ctx::Context) = length(ctx_remaining(ctx))


# -----------------------------------------------------------------------------
# Generic state helpers (optional, but handy)
# -----------------------------------------------------------------------------

# these are just an idea.
effective_state(ctx, fallback) = is_error(ctx.state) ? fallback : unwrap(ctx.state)

mark_state(ctx, s) = @set ctx.state = some(s)

restore_state_marker(ctx, original_marker) = @set ctx.state = original_marker


# -----------------------------------------------------------------------------
# Optional: Parse result types + constructors (include now if you want centralization)
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
#     consumed::Tuple{Vararg{String}}  # keep your current representation for now
#     next::Context{S}
# end

# ParseSuccess(cons::Vector{String}, next::Context{S}) where {S} =
#     ParseSuccess{S}((cons...,), next)

# ParseSuccess(cons::String, next::Context{S}) where {S} =
#     ParseSuccess{S}((cons,), next)

# struct ParseFailure{E}
#     consumed::Int
#     error::E
# end

# const ParseResult{S, E} = Result{ParseSuccess{S}, ParseFailure{E}}

# @inline ParseOk(consumed, next::Context{S}) where {S} = Ok(ParseSuccess(consumed, next))
# @inline ParseErr(consumed::Int, error) = Err(ParseFailure(consumed, error))


function ok(ctx::Context{S}, n::Int; nextctx::Context{S}=consume(ctx, n)) where {S}
    cons = Consumed(ctx.buffer, ctx.pos:(ctx.pos+n-1))
    return ParseOk(cons, nextctx)
end
