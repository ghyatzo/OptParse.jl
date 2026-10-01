#-----------------------------------------
#   Results / Errors
#--------------------------------------------

struct InnerSuccess{S}
    consumed::Consumed
    next::Context{S}
    counts_as_match::Bool
end

Base.convert(::Type{InnerSuccess{S}}, inner::InnerSuccess{S2}) where {S, S2 <: S} =
    @set inner.next = widen_state(S, inner.next)


struct InnerFailure{E}
    consumed::Int
    error::E
end

Base.convert(::Type{InnerFailure{E}}, x::InnerFailure{E2}) where {E, E2 <: E} =
    InnerFailure{E}(x.consumed, x.error)


@sum_type InnerResult{S, E} begin
    innerOk{S}(::InnerSuccess{S})
    innerErr{E}(::InnerFailure{E})
end

innerOk(nextctx::Context{S}, cons::Consumed; as_match = true) where {S} =
    innerOk{S}(InnerSuccess(cons, nextctx, as_match))

innerOk{S}(nextctx::Context{S2}, cons::Consumed; as_match = true) where {S, S2 <: S} =
    return innerOk{S}(InnerSuccess(cons, nextctx, as_match))

innerOk(nextctx::Context{S}, n; as_match = true) where {S} =
    innerOk{S}(consume(nextctx, n)...; as_match)

innerOk{S}(nextctx::Context{S2}, n; as_match = true) where {S, S2 <: S} =
    innerOk{S}(consume(nextctx, n)...; as_match)

innerErr(e::E; consumed = 0) where { E <: AbstractParseError } =
    innerErr{E}(InnerFailure(consumed, e))

innerErr{E}(e::E2; consumed = 0) where { E <: AbstractParseError, E2 <: E} =
    innerErr{E}(InnerFailure(consumed, e))



res_consumed(s::InnerSuccess) = s.consumed
res_num_consumed(f::InnerFailure) = f.consumed
res_num_consumed(s::InnerSuccess) = length(s.consumed)
res_num_consumed(r::InnerResult) = @cases r begin
    innerOk(succ) => res_num_consumed(succ)
    innerErr(fail) => res_num_consumed(fail)
end

res_nextctx(s::InnerSuccess) = s.next
res_nextstate(s::InnerSuccess) = state(res_nextctx(s))
res_matchcounts(s::InnerSuccess) = s.counts_as_match

res_error(f::InnerFailure) = f.error
res_error(r::InnerResult) = @cases r begin
    innerOk(_) => throw(ArgumentError("Cannot get an error from a successful inner result"))
    innerErr(fail) => res_error(fail)
end


# ---- InnerResult widening constructor ----

function InnerResult{S, E}(res::InnerResult) where {S, E}
    @cases res begin
        innerOk(x) => return InnerResult{S, E}'.innerOk(convert(InnerSuccess{S}, x))
        innerErr(x) => return InnerResult{S, E}'.innerErr(convert(InnerFailure{E}, x))
    end
end
