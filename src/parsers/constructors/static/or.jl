# Static (juliac/trim) path for or parser internals.
# Uses @generated function for fully unrolled, type-stable branch search.

@generated function _or_parse_impl(
        parsers::PTup, ctx::Context{OrState{U}}, allconsumed, error
    ) where {PTup <: Tuple, U}

    N = fieldcount(PTup)
    E = Union{ConstrOrError, map(terr, fieldtypes(PTup))...}

    body = quote
        currctx = ctx
    end

    for i in 1:N
        child_parser_t = fieldtype(PTup, i)
        child_parser_tstate = tstate(child_parser_t)
        child_parser_terr = terr(child_parser_t)

        push!(
            body.args, quote
                parser = parsers[$i]::$child_parser_t
                child_state = parser.initialState::$child_parser_tstate
                child_ctx = ctx_with_state(currctx, child_state)

                result = parse(parser, child_ctx)::InnerParseResult{$child_parser_tstate, $child_parser_terr}
                if !is_error(result) && res_num_consumed(result) > 0
                    parse_ok = unwrap(result)

                    if !parse_ok.counts_as_match
                        #=The child parser succeeded, but not in a way that should count
                    as a semantic match for this `or`. Propagate the updated
                    context and keep looking for a real branch match.=#

                        #=No branch has been selected yet. Propagate the updated
                    context, but leave the `or` state unselected so later
                    branches still get a chance to match semantically.=#

                        push!(allconsumed, res_consumed(parse_ok))
                        currctx = ctx_with_state(res_nextctx(parse_ok), ctx_state(currctx))
                    else
                        new_innerstate = some(InnerOrState{$U}(OrBranchState{$i, $child_parser_tstate}(parse_ok)))
                        newctx = widen_restate(OrState{$U}, res_nextctx(parse_ok), new_innerstate)
                        push!(allconsumed, res_consumed(parse_ok))
                        return _OrParseOutcome{OrState{$U}, $E}(
                            OR_OUTCOME_BranchMatch, newctx, merge(allconsumed), error
                        )
                    end
                elseif is_error(result)
                    if res_num_consumed(error) < res_num_consumed(result)
                        parse_err = unwrap_error(result)
                        error = InnerParseFailure{$E}(parse_err)
                    end
                end
            end
        )

    end

    epilogue = quote
        if currctx != ctx
            return _OrParseOutcome{OrState{$U}, $E}(OR_OUTCOME_Propagate, currctx, merge(allconsumed), error)
        end
        return _OrParseOutcome{OrState{$U}, $E}(OR_OUTCOME_NoMatch, currctx, merge(allconsumed), error)
    end

    return quote
        $body
        $epilogue
    end

end


@generated function _or_helpentries_impl(parsers::PTup, rt::OverlayContext) where {PTup <: Tuple}
    ex = quote
        entries = HelpEntry[]
    end
    for (i, type) in enumerate(fieldtypes(PTup))
        push!(
            ex.args,
            :(append!(entries, helpentries(parsers[$i], descend_child(rt))::Vector{HelpEntry}))
        )
    end
    push!(ex.args, :(return entries))
    return ex
end
