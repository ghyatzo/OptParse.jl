# Static (juliac/trim) path for or parser internals.
# Uses @generated function for fully unrolled, type-stable branch search.

@generated function _or_parse_impl(
        parsers::PTup, ctx::Context{OrState{U}}, allconsumed, error
    ) where {PTup <: Tuple, U}

    N = fieldcount(PTup)
    body = quote
        currctx = ctx
    end

    for i in 1:N
        child_parser_t = fieldtype(PTup, i)
        child_parser_tstate = tstate(child_parser_t)

        push!(
            body.args, quote
                parser = parsers[$i]::$child_parser_t
                child_state = parser.initialState::$child_parser_tstate
                child_ctx = ctx_with_state(currctx, child_state)

                result = parse(parser, child_ctx)
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
                        return innerOk(newctx, merge(allconsumed))
                    end
                elseif is_error(result)
                    if res_num_consumed(error) < res_num_consumed(result)
                        error = unwrap_error(result)
                    end
                end
            end
        )

    end

    epilogue = quote
        if currctx != ctx
            return innerOk(currctx, merge(allconsumed), false)
        end
        return innerErr(currctx, error)
    end

    return quote
        $body
        $epilogue
    end

end

parse(p::ConstrOr{T, OrState{U}, _p, PTup}, ctx::Context{OrState{U}}) where {T, U, _p, PTup <: Tuple} = let

    error = ctx_haslessthan(1, ctx) ?
        InnerParseFailure(0, parse_error(ConstrOrError(OR_EndOfInput, "", ""))) :
        InnerParseFailure(0, parse_error(ConstrOrError(OR_UnexpectedToken, ctx_peek(ctx), "")))
    current_ctx = ctx
    allconsumed = Consumed[consumed_empty(ctx)]

    innerstate = ctx_state(ctx)
    has_selection = !is_error(innerstate)

    if has_selection
        selected = unwrap(innerstate)
        res = @unionsplit _parse_branch(p, selected, current_ctx, allconsumed, error)
    else
        res = _or_parse_impl(p.parsers, ctx, allconsumed, error)
    end

    innerstate_U = _or_inner_branch_union(PTup)
    return convert(InnerParseResult{OrState{innerstate_U}}, res)
end

function complete(p::ConstrOr{T}, orstate::OrState{U})::ParseResult{T} where {T, U}
    is_error(orstate) &&
        return typedErr(T, ConstrOrError(OR_NoMatch, "", ""))

    selected = unwrap(orstate)
    return @unionsplit _complete(p, selected)
end

function _complete(
        p::ConstrOr{T, <:OrState{U}},
        selected::OrBranchState{I, S}
    ) where {T, I, S, U}

    child_result = complete(p.parsers[I], ℒ_nextstate(selected.success))
    if is_error(child_result)
        return typedErr(T, unwrap_error(child_result))
    end

    return typedOk(T, unwrap(child_result))
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

function focused_helpdoc(
        p::ConstrOr{T, OrState{U}},
        ctx::Context{OrState{U}},
        prefix::Vector{String},
        rt::OverlayContext
    )::HelpDoc where {T, U}
    is_error(ctx_state(ctx)) && return HelpDoc(
        prefix,
        usage(p),
        helpinfo(rt),
        helpentries(p, descend_child(rt))::Vector{HelpEntry}
    )

    selected = unwrap(ctx_state(ctx))
    return @unionsplit _focused_helpdoc_or(p, selected, prefix, rt)
end

function _focused_helpdoc_or(
        p::ConstrOr, selected::OrBranchState{I, S}, prefix::Vector{String}, rt::OverlayContext
    )::HelpDoc where {I, S}
    return focused_helpdoc(p.parsers[I], res_nextctx(selected.success), prefix, descend_child(rt))
end
