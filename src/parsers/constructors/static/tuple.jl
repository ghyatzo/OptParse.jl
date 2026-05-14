# Static (juliac/trim) path for tuple parser internals.
# Uses @generated functions for fully unrolled, type-stable code.

@generated function _tup_parse_impl(parsers::PTup, ctx::Context{S}) where {PTup <: Tuple, S <: Tuple}

    N = fieldcount(PTup)
    perm, sorted_ptup = _sortperm_by_priority(fieldtypes(parsers))

    whilebody_consumers = Expr(:block)
    whilebody_nonconsumers = Expr(:block)

    for (i, parser_t) in enumerate(sorted_ptup)
        child_parser_tstate = tstate(parser_t)

        push!(
            whilebody_consumers.args, quote
                #= we need to simulate a i in matched_parsers && continue but in an unrolled loop
            # so it becomes a whole if, this unrolled part only happens if it's not yet matched!
            =#
                if $i ∉ matched_parsers
                    parser = parsers[$(perm[i])]

                    child_state = (IndexLens($(perm[i])) ∘ ℒ_state)(current_ctx)::$child_parser_tstate
                    child_ctx = ctx_with_state(current_ctx, child_state)

                    result = parse(parser, child_ctx)::InnerParseResult{$child_parser_tstate}

                    if !is_error(result) && length(unwrap(result).consumed) > 0
                        parse_ok = unwrap(result)

                        if parse_ok.counts_as_match
                            #= parser succeded and consumed input - match it =#
                            newstate = set(ctx_state(current_ctx), IndexLens($(perm[i])), ℒ_nextstate(parse_ok))
                            current_ctx = ctx_with_state(res_nextctx(parse_ok), newstate)

                            push!(allconsumed, ℒ_consumed(parse_ok))

                            push!(matched_parsers, $i)
                            found_match = true
                            #= take the first (highest priority) match that consumes input =#
                            @goto endloop_consumers #= it simulates a "break" by using @goto. =#
                        else
                            #= the inner parser succeded and consumed but by consuming control tokens, not semantic ones
                        # so we update the context with the new information and keep going. =#
                            current_ctx = ctx_with_state(res_nextctx(parse_ok), ctx_state(current_ctx))
                            push!(allconsumed, res_consumed(parse_ok))
                        end

                    elseif is_error(result) && res_num_consumed(error) < res_num_consumed(result)
                        error = unwrap_error(result)
                    end
                end
            end
        )

        # we can generate both unrolls at the same time!
        push!(
            whilebody_nonconsumers.args, quote
                if $i ∉ matched_parsers
                    parser = parsers[$(perm[i])]

                    child_state = (IndexLens($(perm[i])) ∘ ℒ_state)(current_ctx)::$child_parser_tstate
                    child_ctx = ctx_with_state(current_ctx, child_state)

                    result = parse(parser, child_ctx)::InnerParseResult{tstate(parser)}

                    if !is_error(result) && length(unwrap(result).consumed) < 1
                        #=parser succeded without consuming - match it as success=#
                        parse_ok = unwrap(result)

                        newstate = set(ctx_state(current_ctx), IndexLens($(perm[i])), ℒ_nextstate(parse_ok))
                        current_ctx = ctx_with_state(res_nextctx(parse_ok), newstate)

                        push!(matched_parsers, $i)
                        found_match = true
                        #= take the first (highest priority) match that consumes input =#
                        @goto endloop_nonconsumers
                    elseif is_error(result) && res_num_consumed(result) < 1
                        #=parser failed without consuming input, this could be an optional
                    # parser that doesn't match.
                    # mark it as matched anyway.
                    =#
                        push!(matched_parsers, $i)
                        found_match = true
                        @goto endloop_nonconsumers
                    end
                end
            end
        )
    end

    return quote
        current_ctx = ctx
        allconsumed = Consumed[consumed_empty(ctx)]
        matched_parsers = Set{Int}()

        while length(matched_parsers) < length(parsers)
            found_match = false

            error = InnerParseFailure(
                0,
                constrtuple_error(
                    TUPLE_NoRemainingParser;
                    token = ctx_hasmore(current_ctx) > 0 ? ctx_peek(current_ctx) : "",
                )
            )

            #= instead of filtering by the already matched parsers
            # we iterate over all parsers and skip those already matched.
            # this way we know which parser we're working with at compile time.
            # less efficient computationally but at least type stable
            =#
            j = 0
            $whilebody_consumers
            @label endloop_consumers

            #=if no consuming parser is matched, try non consuming ones (like optional or constant)=#
            if !found_match
                $whilebody_nonconsumers
                @label endloop_nonconsumers
            end

            if !found_match
                #=If we still haven't found a match then cry=#
                return innerErr(current_ctx, error)
            end
        end

        mergedcons = merge(allconsumed)
        return innerOk(current_ctx, mergedcons)
    end

end

@generated function _tuple_complete_impl(p::PTup, state::STup) where {PTup <: Tuple, STup <: Tuple}
    Ps = PTup.parameters
    Ss = STup.parameters
    T = Tuple{map(tval, Ps)...}

    ex = Expr(:block, :(output = ()))
    for i in eachindex(Ps)
        Ti = tval(Ps[i])
        S = Ss[i]
        push!(
            ex.args, quote
                child_state = state[$i]::$S
                child_parser = p[$i]

                result = (complete(child_parser, child_state))::ParseResult{$Ti}
                if is_error(result)
                    return false, ParseResult{$T}(typedErr(unwrap_error(result)))
                end

                output = insert(output, IndexLens($i), unwrap(result))
            end
        )
    end
    push!(ex.args, :(return true, output::$T))

    return ex
end

