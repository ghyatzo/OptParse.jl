# Dynamic (interactive) path for or parser internals.
# Uses runtime loop with @nospecialize to avoid per-tree compilation.

function _or_parse_impl(@nospecialize(parsers::Tuple), @nospecialize(ctx::Context), allconsumed, error)
    U = _or_inner_branch_union(typeof(parsers))

    currctx = ctx
    for (i, parser) in enumerate(parsers)
        child_state = parser.initialState
        child_ctx = ctx_with_state(currctx, child_state)

        result = parse(parser, child_ctx)
        if !is_error(result) && res_num_consumed(result) > 0
            parse_ok = unwrap(result)

            if !parse_ok.counts_as_match
                push!(allconsumed, res_consumed(parse_ok))
                currctx = ctx_with_state(res_nextctx(parse_ok), ctx_state(currctx))
            else
                child_tstate = typeof(child_state)
                new_innerstate = some(InnerOrState{U}(OrBranchState{i, child_tstate}(parse_ok)))
                OrS = OrState{U}
                newctx = widen_restate(OrS, res_nextctx(parse_ok), new_innerstate)
                push!(allconsumed, res_consumed(parse_ok))
                return innerOk(newctx, merge(allconsumed))
            end
        elseif is_error(result)
            if res_num_consumed(error) < res_num_consumed(result)
                error = unwrap_error(result)
            end
        end
    end

    if currctx != ctx
        return innerOk(currctx, merge(allconsumed), false)
    end
    return innerErr(currctx, error)
end

function parse(@nospecialize(p::ConstrOr), @nospecialize(ctx::Context))
    PTup = ptypes(typeof(p))

    error = ctx_haslessthan(1, ctx) ?
        InnerParseFailure(0, constror_error(OR_EndOfInput)) :
        InnerParseFailure(0, constror_error(OR_UnexpectedToken; token = ctx_peek(ctx)))
    current_ctx = ctx
    allconsumed = Consumed[consumed_empty(ctx)]

    innerstate = ctx_state(ctx)
    has_selection = !is_error(innerstate)

    if has_selection
        selected = unwrap(innerstate)
        res = _parse_branch(p, unwrapunion(selected), current_ctx, allconsumed, error)
    else
        res = _or_parse_impl(p.parsers, ctx, allconsumed, error)
    end

    innerstate_U = _or_inner_branch_union(PTup)
    return convert(InnerParseResult{OrState{innerstate_U}}, res)
end

function complete(@nospecialize(p::ConstrOr), @nospecialize(orstate))
    T = tval(typeof(p))
    is_error(orstate) &&
        return typedErr(T, constror_error(OR_NoMatch))

    selected = unwrap(orstate)
    return _complete(p, unwrapunion(selected))
end

function _complete(
        @nospecialize(p::ConstrOr),
        selected::OrBranchState{I, S}
    ) where {I, S}
    T = tval(typeof(p))

    child_result = complete(p.parsers[I], ℒ_nextstate(selected.success))
    if is_error(child_result)
        return typedErr(
            T, error_with_subject(
                child_result, "or"
            )
        )
    end

    return typedOk(T, unwrap(child_result))
end

function _or_helpentries_impl(@nospecialize(parsers::Tuple), rt::OverlayContext)
    entries = HelpEntry[]
    for child in parsers
        append!(entries, helpentries(child, descend_child(rt))::Vector{HelpEntry})
    end
    return entries
end

function focused_helpdoc(
        @nospecialize(p::ConstrOr), @nospecialize(ctx::Context),
        prefix::Vector{String}, rt::OverlayContext
    )
    is_error(ctx_state(ctx)) && return HelpDoc(
        prefix,
        usage(p),
        helpinfo(rt),
        helpentries(p, descend_child(rt))::Vector{HelpEntry}
    )

    selected = unwrap(ctx_state(ctx))
    return _focused_helpdoc_or(p, unwrapunion(selected), prefix, rt)
end

function _focused_helpdoc_or(
        @nospecialize(p::ConstrOr),
        selected::OrBranchState{I, S}, prefix::Vector{String}, rt::OverlayContext
    ) where {I, S}
    return focused_helpdoc(p.parsers[I], res_nextctx(selected.success), prefix, descend_child(rt))
end
