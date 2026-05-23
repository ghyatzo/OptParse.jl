# Static (juliac/trim) path for tuple parser internals.
# Uses @generated functions for fully unrolled, type-stable code.

@generated function _tup_parse_impl(parsers::PTup, ctx::Context{S}) where {PTup <: Tuple, S <: Tuple}

    N = fieldcount(PTup)
    perm, sorted_ptup = _sortperm_by_priority(fieldtypes(parsers))
    E = Union{ConstrTupleError, map(p -> terr(p), fieldtypes(PTup))...}

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
                        parse_err = unwrap_error(result)
                        error = InnerParseFailure{$E}(parse_err.consumed, parse_err.error)
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

            error = InnerParseFailure{$E}(
                0,
                ConstrTupleError(
                    TUPLE_NoRemainingParser,
                    ctx_hasmore(current_ctx) > 0 ? ctx_peek(current_ctx) : "",
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
                return current_ctx, error, merge(allconsumed), found_match
            end
        end

        return current_ctx, error, merge(allconsumed), true
    end

end

@generated function _tuple_complete_impl(p::PTup, state::STup) where {PTup <: Tuple, STup <: Tuple}
    Ps = PTup.parameters
    Ss = STup.parameters
    T = Tuple{map(tval, Ps)...}
    E = Union{ConstrTupleError, map(terr, Ps)...}

    ex = Expr(:block)

    # Phase 1: complete each child into a typed local, early-return on error
    for i in eachindex(Ps)
        S = Ss[i]
        result_sym = Symbol("result_", i)
        push!(
            ex.args, quote
                child_state = state[$i]::$S
                child_parser = p[$i]
                $result_sym = complete(child_parser, child_state)
                is_error($result_sym) && return Result{$T, $E}(typedErr($E, unwrap_error($result_sym)))
            end
        )
    end

    # Phase 2: construct the Tuple from all successful results
    unwraps = [:(unwrap($(Symbol("result_", i)))::$(tval(Ps[i]))) for i in eachindex(Ps)]
    push!(ex.args, :(return Result{$T, $E}(typedOk($T, ($(unwraps...),)::$T))))

    return ex
end

@generated function _tuple_helpentries_impl(parsers::PTup, rt::OverlayContext) where {PTup <: Tuple}
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

@generated function _focused_helpdoc_tuple(
        p::ConstrTuple{T, <:Any, S, PTup},
        ctx::Context{S},
        prefix::Vector{String},
        rt::OverlayContext
    ) where {T, PTup <: Tuple, S <: Tuple}
    N = fieldcount(PTup)
    body = Expr(:block)

    for i in 1:N
        child_state_t = fieldtype(S, i)
        push!(
            body.args, quote
                child_state = ctx_state(ctx)[$i]::$child_state_t
                child_ctx = widen_restate($child_state_t, ctx, child_state)
                child_helpdoc = (focused_helpdoc(p.parsers[$i], child_ctx, prefix, descend_child(rt)))::HelpDoc

                if child_helpdoc.prefix != prefix
                    return child_helpdoc
                end

                append!(entries, helpentries(p.parsers[$i], descend_child(rt))::Vector{HelpEntry})
            end
        )
    end

    return quote
        entries = HelpEntry[]
        $body
        return HelpDoc(prefix, usage(p), helpinfo(rt), entries)
    end
end