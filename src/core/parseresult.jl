#-----------------------------------------
#   Results / Errors
#--------------------------------------------


struct InnerParseSuccess{S}
    consumed::Consumed
    next::Context{S}
    counts_as_match::Bool
end

Base.convert(::InnerParseSuccess{S}, inner::InnerParseSuccess{S2}) where {S, S2 <: S} =
    @set inner.next = widen_state(S, inner.next)


struct InnerParseFailure{E}
    consumed::Int
    error::E
end

# convert calls this.
InnerParseFailure{E}(x::InnerParseFailure{E2}) where {E, E2 <: E} =
    InnerParseFailure{E}(x.consumed, x.error)


const InnerParseResult{S, E} = Result{InnerParseSuccess{S}, InnerParseFailure{E}}


res_consumed(s::InnerParseSuccess) = s.consumed
res_num_consumed(f::InnerParseFailure) = f.consumed
res_num_consumed(s::InnerParseSuccess) = length(s.consumed)
res_num_consumed(r::InnerParseResult) = @cases r begin
    Ok(x) => res_num_consumed(x)
    Err(x) => res_num_consumed(x)
end

res_nextctx(s::InnerParseSuccess) = s.next
res_nextstate(s::InnerParseSuccess) = state(res_nextctx(s))
res_matchcounts(s::InnerParseSuccess) = s.counts_as_match

res_error(f::InnerParseFailure) = f.error
res_error(r::InnerParseResult) = res_error(unwrap_error(r))


# ---- InnerParseResult widening constructors ----
# innerOk/innerErr return results with one type parameter still `Union{}`;
# these constructors complete it, rebuilding the payload when the state or
# error type widens. (Widening without payload rebuild rides the generic
# `Result{T1,E1}` constructor in SumResults; these win dispatch because their
# argument shapes are more specific.)

function InnerParseResult{S, E}(x::Result{InnerParseSuccess{S2}, Uninit}) where {S, E, S2 <: S}
    inner = unwrap(x)
    return Result{InnerParseSuccess{S}, InnerParseFailure{E}}'.Ok(
        @set inner.next = widen_state(S, inner.next)
    )
end

function InnerParseResult{S, E}(x::Result{Uninit, InnerParseFailure{E2}}) where {S, E, E2 <: E}
    inner = unwrap_error(x)
    return Result{InnerParseSuccess{S}, InnerParseFailure{E}}'.Err(
        InnerParseFailure{E}(inner)
    )
end

# Trim-safe widening from a child InnerParseResult with narrower S2/E2 to wider S/E.
function InnerParseResult{S, E}(res::Result{InnerParseSuccess{S2}, InnerParseFailure{E2}}) where {S, E, S2 <: S, E2 <: E}
    @cases res begin
        Ok(x) => return Result{InnerParseSuccess{S}, InnerParseFailure{E}}'.Ok(
            @set x.next = widen_state(S, x.next)
        )
        Err(x) => return Result{InnerParseSuccess{S}, InnerParseFailure{E}}'.Err(
            InnerParseFailure{E}(x)
        )
    end
end

# ---- InnerParseResult helpers ----

# Success: leaves E unset → completed by the widening constructor above.
function innerOk(nextctx::Context, cons::Consumed; counts_as_match = true)
    return Ok(InnerParseSuccess(cons, nextctx, counts_as_match))
end

function innerOk(nextctx::Context, n; counts_as_match = true)
    return innerOk(consume(nextctx, n)...; counts_as_match)
end

# Failure from concrete error: leaves the success parameter unset.
function innerErr(e::AbstractParseError; consumed = 0)
    return Err(InnerParseFailure(consumed, e))
end

# Failure by widening child result. Use this when E is a union or when the
# child result's error type needs widening.
function innerErr(::Type{E}, res::InnerParseResult) where {E}
    @assert is_error(res)
    child_err = unwrap_error(res)
    return Err(InnerParseFailure{E}(child_err.consumed, child_err.error))
end

# ---- ParseResult helpers ----

const ParseResult{T, E} = Result{T, E}
