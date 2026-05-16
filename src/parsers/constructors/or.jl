@wrapped struct InnerOrState{U}
    union::U
end

struct OrBranchState{I, S}
    success::InnerParseSuccess{S}
end

branch_idx(::Type{OrBranchState{I, S}}) where {I, S} = I
branch_state(::Type{OrBranchState{I, S}}) where {I, S} = S

const OrState{U} = Option{InnerOrState{U}}

_inner_state(::Type{<:OrState{U}}) where {U} = U

@enum OrErrCode::UInt8 begin
    OR_EndOfInput
    OR_UnexpectedToken
    OR_Conflict
    OR_NoMatch
    OR_Unreachable
end

constror_error(code::OrErrCode; token = "", detail = "", subject = "") =
    mkerror(
    ParsePhase, ERR_ConstrOr, UInt8(code);
    token,
    detail,
    trace = isempty(subject) ? ErrorSite[] : ErrorSite[ErrorSite(ParsePhase, ERR_ConstrOr, subject)]
)

function constror_render_error(io::IO, code::OrErrCode, err::ParseError)
    return if code == OR_EndOfInput
        print(io, "Expected an option or command, got end of input")
    elseif code == OR_UnexpectedToken
        print(io, "Unexpected option or subcommand: $(err.token)")
    elseif code == OR_Conflict
        print(io, "$(err.detail) and $(err.token) can't be used together")
    elseif code == OR_NoMatch
        print(io, "No matching option or command")
    elseif code == OR_Unreachable
        print(io, "Internal error: reached an unreachable or-branch state")
    else
        print(io, "unreachable")
    end
end

Base.@assume_effects :foldable function _or_inner_branch_union(::Type{PTup}) where {PTup <: Tuple}
    branch_types = ntuple(fieldcount(PTup)) do i
        ptype = fieldtype(PTup, i)
        OrBranchState{i, tstate(ptype)}
    end
    return Union{branch_types...}
end

# a parser that returns the first parsers that matches, in the order provided!
struct ConstrOr{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    parsers::P
end

ConstrOr(parsers::PTup) where {PTup <: Tuple} = let

    innerstate_U = _or_inner_branch_union(PTup)

    ConstrOr{
        Union{map(tval, parsers)...},
        OrState{innerstate_U},
        mapreduce(p -> priority(p), max, parsers),
        typeof(parsers),
    }(none(InnerOrState{innerstate_U}), parsers)
end

@inline @autospecialize p function usage(p::ConstrOr)
    UsageAlternative(_usage_children(p.parsers))
end
# _or_helpentries_impl is provided by static/or.jl or dynamic/or.jl
# focused_helpdoc is provided by static/or.jl or dynamic/or.jl

@autospecialize p function helpentries(p::ConstrOr{T, S, _p, PTup}, rt::OverlayContext) where {T, S <: OrState, _p, PTup <: Tuple}
    return _or_helpentries_impl(p.parsers, rt)
end


@autospecialize p selected currctx function _parse_branch(
        p::ConstrOr{T, <:U}, selected::OrBranchState{I, S}, currctx::Context{U},
        allconsumed::Vector{Consumed}, error::InnerParseFailure
    ) where {T, U, I, S}

    child_state = ℒ_nextstate(selected.success)
    child_ctx = ctx_with_state(currctx, child_state)

    result = parse(p.parsers[I], child_ctx)
    if !is_error(result) && res_num_consumed(result) > 0
        parse_ok = unwrap(result)

        new_innerstate = some(InnerOrState{_inner_state(U)}(OrBranchState{I, S}(parse_ok)))
        newctx = widen_restate(OrState{_inner_state(U)}, res_nextctx(parse_ok), new_innerstate)
        push!(allconsumed, res_consumed(parse_ok))

        if !parse_ok.counts_as_match
            #=The child parser succeeded, but not in a way that should count
            as a semantic match for this `or`. Propagate the updated
            context and keep looking for a real branch match.=#

            #=We are already inside this same branch. Preserve that
            selection while surfacing the control-side-effect.=#
            if newctx != currctx
                return innerOk(newctx, merge(allconsumed), false)
            else
                return innerErr(newctx, error)
            end
        else
            return innerOk(newctx, merge(allconsumed))
        end
    elseif is_error(result)
        #= the child parser has encountered an error, we should resurface that error instead of the generic =#
        error = error_with_trace(
            result, ParsePhase, ERR_ConstrOr, "or"
        )
    end

    return innerErr(currctx, error)
end

# _or_parse_impl is provided by static/or.jl or dynamic/or.jl
# parse and complete are provided by static/or.jl or dynamic/or.jl
