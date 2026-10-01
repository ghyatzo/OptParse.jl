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
        inner.consumed,
        widen_state(S, inner.next),
        inner.counts_as_match
    )
end

struct InnerParseFailure{E}
    consumed::Int
    error::E
end

InnerParseFailure{E}(x::InnerParseFailure{E2}) where {E, E2 <: E} = InnerParseFailure{E}(x.consumed, x.error)

const InnerParseResult{S, E} = Result{InnerParseSuccess{S}, InnerParseFailure{E}}


res_consumed(s::InnerParseSuccess) = s.consumed
res_num_consumed(f::InnerParseFailure) = f.consumed
res_num_consumed(s::InnerParseSuccess) = length(s.consumed)
res_num_consumed(r::InnerParseResult) =
    is_error(r) ? res_num_consumed(unwrap_error(r)) : res_num_consumed(unwrap(r))

res_nextctx(s::InnerParseSuccess) = s.next
res_nextstate(s::InnerParseSuccess) = state(res_nextctx(s))
res_matchcounts(s::InnerParseSuccess) = s.counts_as_match

res_error(f::InnerParseFailure) = f.error
res_error(r::InnerParseResult) = res_error(unwrap_error(r))


# ---- InnerParseResult widening constructors ----
# These accept ResultConstructors from innerOk/innerErr and widen type params.
# Used by the untyped innerOk/innerErr helpers (concrete types only).

function InnerParseResult{S, E}(x::ErrorTypes.ResultConstructor{InnerParseSuccess{S2}, Ok}) where {S, E, S2 <: S}
    inner = x.x
    return Result{InnerParseSuccess{S}, InnerParseFailure{E}}(typedOk(InnerParseSuccess{S},
        InnerParseSuccess(
            inner.consumed,
            widen_state(S, inner.next),
            inner.counts_as_match
        )
    ))
end

function InnerParseResult{S, E}(x::ErrorTypes.ResultConstructor{InnerParseFailure{E2}, <:Err}) where {S, E, E2 <: E}
    inner = x.x
    return Result{InnerParseSuccess{S}, InnerParseFailure{E}}(
        typedErr(InnerParseFailure{E}, InnerParseFailure{E}(inner.consumed, inner.error)
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
