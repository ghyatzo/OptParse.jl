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

InnerResult{T, Uninit}(x::InnerResult{T, Uninit}) where {T} = x
InnerResult{Uninit, E}(x::InnerResult{Uninit, E}) where {E} = x
Base.convert(::Type{InnerResult{T, Uninit}}, x::InnerResult{T, Uninit}) where {T} = x
Base.convert(::Type{InnerResult{Uninit, E}}, x::InnerResult{Uninit, E}) where {E} = x

function InnerResult{S, E}(res::InnerResult) where {S, E}
    @cases res begin
        innerOk(x) => return InnerResult{S, E}'.innerOk(convert(InnerSuccess{S}, x))
        innerErr(x) => return InnerResult{S, E}'.innerErr(convert(InnerFailure{E}, x))
    end
end

innerOk(nextctx::Context{S}, cons::Consumed; counts_as_match = true) where {S} =
    innerOk{S}(InnerSuccess(cons, nextctx, counts_as_match))

innerOk{S}(nextctx::Context{S2}, cons::Consumed; counts_as_match = true) where {S, S2 <: S} =
    innerOk{S}(InnerSuccess(cons, nextctx, counts_as_match))

innerOk(nextctx::Context{S}, n; counts_as_match = true) where {S} =
    innerOk{S}(consume(nextctx, n)...; counts_as_match)

innerOk{S}(nextctx::Context{S2}, n; counts_as_match = true) where {S, S2 <: S} =
    innerOk{S}(consume(nextctx, n)...; counts_as_match)

innerErr(e::E; consumed = 0) where { E <: AbstractParseError } =
    innerErr{E}(InnerFailure(consumed, e))

innerErr{E}(e::E2; consumed = 0) where { E <: AbstractParseError, E2 <: E} =
    innerErr{E}(InnerFailure(consumed, e))

#=Widen a failed child result to the parent's error type, preserving the
consumed-token count.=#
innerErr{E}(res::InnerResult) where {E} =
    innerErr{E}(convert(InnerFailure{E}, unwrap_error(res)))


SumResults.is_error(x::InnerResult) = @cases x begin
    innerOk => false
    innerErr => true
end


function SumResults.unwrap(x::InnerResult{T,E})::InnerSuccess{T} where {T, E}
    @cases x begin
        innerOk(v) => v
        innerErr => throw(ArgumentError("unwrap called on an Err result"))
    end
end


function SumResults.unwrap_error(x::InnerResult{T,E})::InnerFailure{E} where {T, E}
    @cases x begin
        innerOk => throw(ArgumentError("unwrap_error called on an Ok result"))
        innerErr(e) => e
    end
end

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
