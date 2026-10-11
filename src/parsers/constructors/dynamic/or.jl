# Dynamic (interactive) path for or parser internals.
# Uses runtime loop with @nospecialize to avoid per-tree compilation.

function _or_parse_impl(@nospecialize(parsers::Tuple), @nospecialize(ctx::Context), allconsumed, error)
    U = _or_inner_branch_union(typeof(parsers))
    E = reduce(joinerr, map(err_t, parsers), init = ConstrOrError)

    currctx = ctx
    for (i, parser) in enumerate(parsers)
        child_state = parser.initialState
        child_ctx = with_state(currctx, child_state)

        result = parse(parser, child_ctx)
        if !is_error(result) && res_num_consumed(result) > 0
            parse_ok = unwrap(result)

            if !parse_ok.counts_as_match
                push!(allconsumed, res_consumed(parse_ok))
                currctx = with_state(res_nextctx(parse_ok), state(currctx))
            else
                child_tstate = typeof(child_state)
                new_innerstate = OrState{U}'.Selected(InnerOrState{U}(OrBranchState{i, child_tstate}(parse_ok)))
                newctx = widen_restate(OrState{U}, res_nextctx(parse_ok), new_innerstate)
                push!(allconsumed, res_consumed(parse_ok))

                return OrParseOutcome{OrState{U}, E}'.BranchMatch(
                    OrOutcomePayload(newctx, merge(allconsumed), error)
                )
            end
        elseif is_error(result)
            if res_num_consumed(error) < res_num_consumed(result)
                error = convert(InnerFailure{E}, unwrap_error(result))
            end
        end
    end

    if currctx != ctx
        return OrParseOutcome{OrState{U}, E}'.Propagate(OrOutcomePayload(currctx, merge(allconsumed), error))
    end
    return OrParseOutcome{OrState{U}, E}'.NoMatch(OrOutcomePayload(currctx, merge(allconsumed), error))
end

function _or_helpentries_impl(@nospecialize(parsers::Tuple), rt::OverlayContext)
    entries = HelpEntry[]
    for child in parsers
        append!(entries, helpentries(child, descend_child(rt))::Vector{HelpEntry})
    end
    return entries
end
