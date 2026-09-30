@wrapped struct InnerOrState{U}
    union::U
end

struct OrBranchState{I, S}
    success::InnerParseSuccess{S}
end

branch_idx(::Type{OrBranchState{I, S}}) where {I, S} = I
branch_state(::Type{OrBranchState{I, S}}) where {I, S} = S

@sum_type OrState{U} :hidden begin
    NotMatched
    Selected{U}(branch::InnerOrState{U})
end

_inner_state(::Type{<:OrState{U}}) where {U} = U


@enum OrErrCode::UInt8 begin
    OR_EndOfInput
    OR_UnexpectedToken
    OR_Conflict
    OR_NoMatch
    OR_Unreachable
end

struct ConstrOrError <: AbstractParseError
    code::OrErrCode
    token::String
    detail::String
end

function render_error(io::IO, err::ConstrOrError)
    return if err.code == OR_EndOfInput
        print(io, "Expected an option or command, got end of input")
    elseif err.code == OR_UnexpectedToken
        print(io, "Unexpected option or subcommand: $(err.token)")
    elseif err.code == OR_Conflict
        print(io, "$(err.detail) and $(err.token) can't be used together")
    elseif err.code == OR_NoMatch
        print(io, "No matching option or command")
    elseif err.code == OR_Unreachable
        print(io, "Internal error: reached an unreachable or-branch state")
    else
        print(io, "unreachable")
    end
end

Base.@assume_effects :foldable function _or_inner_branch_union(::Type{PTup}) where {PTup <: Tuple}
    branch_types = ntuple(fieldcount(PTup)) do i
        ptype = fieldtype(PTup, i)
        OrBranchState{i, state_t(ptype)}
    end
    return Union{branch_types...}
end

# a parser that returns the first parsers that matches, in the order provided!
struct ConstrOr{T, E, S, P, R} <: AbstractParser{T, E, S, P, R}
    initialState::S
    parsers::P

    ConstrOr(parsers::PTup) where {PTup <: Tuple} = let

        innerstate_U = _or_inner_branch_union(PTup)

        new{
            Union{map(val_t, parsers)...},
            reduce(joinerr, map(err_t, parsers), init = ConstrOrError),
            OrState{innerstate_U},
            typeof(parsers),
            mapreduce(p -> priority(p), max, parsers),
        }(OrState{innerstate_U}'.NotMatched, parsers)
    end
end


@autospecialize p function usage(p::ConstrOr)
    UsageAlternative(_usage_children(p.parsers))
end
# _or_helpentries_impl is provided by static/or.jl or dynamic/or.jl
# focused_helpdoc is provided by static/or.jl or dynamic/or.jl

@autospecialize p function helpentries(p::ConstrOr{T, _E, S, PTup}, rt::OverlayContext) where {T, _E, S <: OrState, PTup <: Tuple}
    return _or_helpentries_impl(p.parsers, rt)
end

@autospecialize p ctx function focused_helpdoc(
        p::ConstrOr{T, <:Any, OrState{U}},
        ctx::Context{OrState{U}},
        prefix::Vector{String},
        rt::OverlayContext
    )::HelpDoc where {T, U}
    selected = @cases state(ctx) begin
        NotMatched => return HelpDoc(
            prefix,
            usage(p),
            helpinfo(rt),
            helpentries(p, descend_child(rt))::Vector{HelpEntry}
        )
        Selected(branch) => branch
    end

    return @static if juliac
        @unionsplit _focused_helpdoc_or(p, selected, prefix, rt)
    else
        _focused_helpdoc_or(p, unwrapunion(selected), prefix, rt)
    end
end

@autospecialize p function _focused_helpdoc_or(
        p::ConstrOr, selected::OrBranchState{I, S}, prefix::Vector{String}, rt::OverlayContext
    )::HelpDoc where {I, S}
    return focused_helpdoc(p.parsers[I], res_nextctx(selected.success), prefix, descend_child(rt))
end


@enum _OrParseOutcomeKind begin
    OR_OUTCOME_BranchMatch
    OR_OUTCOME_Propagate
    OR_OUTCOME_NoMatch
end

struct _OrParseOutcome{S, E}
    kind::_OrParseOutcomeKind
    ctx::Context{S}
    allconsumed::Consumed
    error::InnerParseFailure{E}
end


@autospecialize p ctx function parse(p::ConstrOr{T, E, S, PTup}, ctx::Context{S}) where {T, E, S <: OrState, PTup <: Tuple}

    error = InnerParseFailure{E}(
        0, hasnone(ctx) ?
            ConstrOrError(OR_EndOfInput, "", "") :
            ConstrOrError(OR_UnexpectedToken, peek(ctx), "")
    )
    current_ctx = ctx
    allconsumed = Consumed[consumed_empty(ctx)]

    outcome = @cases state(ctx) begin
        NotMatched => _or_parse_impl(p.parsers, ctx, allconsumed, error)
        Selected(branch) => begin
            @static if juliac
                @unionsplit _parse_branch(p, branch, current_ctx, allconsumed, error)
            else
                _parse_branch(p, unwrapunion(branch), current_ctx, allconsumed, error)
            end
        end
    end

    if outcome.kind == OR_OUTCOME_BranchMatch
        return InnerParseResult{S, E}(innerOk(outcome.ctx, outcome.allconsumed))
    elseif outcome.kind == OR_OUTCOME_Propagate
        return InnerParseResult{S, E}(innerOk(outcome.ctx, outcome.allconsumed; counts_as_match = false))
    elseif outcome.kind == OR_OUTCOME_NoMatch
        return InnerParseResult{S, E}(Err(outcome.error))
    else
        error("unreachable")
    end
end

# _or_parse_impl is provided by static/or.jl or dynamic/or.jl

@autospecialize p selected currctx function _parse_branch(
        p::ConstrOr{T, E, U}, selected::OrBranchState{I, S}, currctx::Context{U},
        allconsumed::Vector{Consumed}, error::InnerParseFailure
    ) where {T, E, U <: OrState, I, S}

    child_state = res_nextstate(selected.success)
    child_ctx = with_state(currctx, child_state)

    result = parse(p.parsers[I], child_ctx)
    if !is_error(result) && res_num_consumed(result) > 0
        parse_ok = unwrap(result)

        new_innerstate = U'.Selected(InnerOrState{_inner_state(U)}(OrBranchState{I, S}(parse_ok)))
        newctx = widen_restate(U, res_nextctx(parse_ok), new_innerstate)
        push!(allconsumed, res_consumed(parse_ok))

        if !parse_ok.counts_as_match
            #=The child parser succeeded, but not in a way that should count
            as a semantic match for this `or`. Propagate the updated
            context and keep looking for a real branch match.=#

            #=We are already inside this same branch. Preserve that
            selection while surfacing the control-side-effect.=#
            if newctx != currctx
                return _OrParseOutcome{U, E}(OR_OUTCOME_Propagate, newctx, merge(allconsumed), error)
            else
                return _OrParseOutcome{U, E}(OR_OUTCOME_NoMatch, newctx, merge(allconsumed), error)
            end
        else
            return _OrParseOutcome{U, E}(OR_OUTCOME_BranchMatch, newctx, merge(allconsumed), error)
        end
    elseif is_error(result)
        #= the child parser has encountered an error, we should resurface that error instead of the generic =#
        error = InnerParseFailure{E}(unwrap_error(result))
    end

    return _OrParseOutcome{U, E}(OR_OUTCOME_NoMatch, currctx, merge(allconsumed), error)
end


@autospecialize p orstate function complete(p::ConstrOr{T, E}, orstate::OrState{U}) where {T, E, U}
    selected = @cases orstate begin
        NotMatched => return ParseResult{T, E}(typedErr(E, ConstrOrError(OR_NoMatch, "", "")))
        Selected(branch) => branch
    end
    return @static if juliac
        @unionsplit _complete(p, selected)::ParseResult{T, E}
    else
        _complete(p, unwrapunion(selected))
    end
end


@autospecialize p function _complete(
        p::ConstrOr{T, E, <:OrState{U}},
        selected::OrBranchState{I, S}
    ) where {T, E, I, S, U}

    child_result = complete(p.parsers[I], res_nextstate(selected.success))
    if is_error(child_result)
        return ParseResult{T, E}(Err(unwrap_error(child_result)))
    end

    return ParseResult{T, E}(Ok(unwrap(child_result)))
end
