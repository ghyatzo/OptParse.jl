struct ConstrTuple{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    parsers::P
    #
    label::String
end

@enum TupleErrCode::UInt8 begin
    TUPLE_NoRemainingParser
end

constrtuple_error(code::TupleErrCode; token = "", detail = "", subject="") =
    mkerror(ParsePhase, ERR_ConstrTuple, UInt8(code);
        token,
        detail,
        context= isempty(subject) ? ErrorSite[] : ErrorSite[ErrorSite(ParsePhase, ERR_ConstrTuple, subject)]
    )

function constrtuple_render_error(io::IO, code::TupleErrCode, err::ParseError)
    if code == TUPLE_NoRemainingParser
        if isempty(err.token)
            print(io, "No remaining parsers could match the input")
        else
            print(io, "No remaining parsers could match $(err.token)")
        end
    else
        print(io, "unreachable")
    end
end

ConstrTuple(parsers::PTup; label::String = "") where {PTup} = let
    ConstrTuple{
        Tuple{map(tval, parsers)...},
        Tuple{map(tstate, parsers)...},
        mapreduce(priority, max, parsers, init = 0),
        PTup,
    }(map(p -> p.initialState, parsers), parsers, label)
end

Base.@assume_effects :foldable function _sortperm_by_priority(p::PTup) where {PTup <: Tuple}
    perm = _sortperm(p, rev = true, by = priority)
    permp = ntuple(fieldcount(PTup)) do i
        @inbounds(p[perm[i]])
    end
    return perm, permp
end

sortperm_tuple(p::PTup) where {PTup <: Tuple} = _sortperm_by_priority(p)


@generated function _generated_tup_parse(parsers::PTup, ctx::Context{S}) where {PTup <: Tuple, S <: Tuple}

    N = fieldcount(PTup)
    perm, sorted_ptup = _sortperm_by_priority(fieldtypes(parsers))

    whilebody_consumers = Expr(:block)
    whilebody_nonconsumers = Expr(:block)

    for (i, parser_t) in enumerate(sorted_ptup)
        child_parser_tstate = tstate(parser_t)

        push!(whilebody_consumers.args, quote
            # child_state = ℒ_state(current_ctx)[$(perm[i])]
            #= we need to simulate a i in matched_parsers && continue but in an unrolled loop
            # so it becomes a whole if, this unrolled part only happens if it's not yet matched!
            =#
            if $i ∉ matched_parsers
                parser = parsers[$(perm[i])]

                child_state = (IndexLens($(perm[i])) ∘ ℒ_state)(current_ctx)::$child_parser_tstate
                child_ctx = ctx_with_state(current_ctx, child_state)

                result = parse(unwrapunion(parser), child_ctx)::InnerParseResult{$child_parser_tstate}

                if !is_error(result) && length(unwrap(result).consumed) > 0
                    #= parser succeded and consumed input - match it =#
                    parse_ok = unwrap(result)

                    newstate = set(ℒ_state(current_ctx), IndexLens($(perm[i])), ℒ_nextstate(parse_ok))
                    current_ctx = ctx_with_state(ℒ_nextctx(parse_ok), newstate)

                    push!(allconsumed, ℒ_consumed(parse_ok))
                    push!(matched_parsers, $i)
                    found_match = true
                    #= take the first (highest priority) match that consumes input =#
                    @goto endloop_consumers #= it simulates a "break" by using @goto.
                    # tecnically the @unroll macro also already uses a "loopend" label, but It seems that
                    # these goto macros are expanded before the @unroll and therefore is not there yet. =#
                elseif is_error(result) && error.consumed < unwrap_error(result).consumed
                    error = unwrap_error(result)
                end
            end
        end)

        # we can generate both unrolls at the same time!
        push!(whilebody_nonconsumers.args, quote
            if $i ∉ matched_parsers
                parser = parsers[$(perm[i])]

                child_state = (IndexLens($(perm[i])) ∘ ℒ_state)(current_ctx)::$child_parser_tstate
                child_ctx = ctx_with_state(current_ctx, child_state)

                result = parse(unwrapunion(parser), child_ctx)::InnerParseResult{tstate(parser)}

                if !is_error(result) && length(unwrap(result).consumed) < 1
                    #=parser succeded without consuming - match it as success=#
                    parse_ok = unwrap(result)

                    newstate = set(ℒ_state(current_ctx), IndexLens($(perm[i])), ℒ_nextstate(parse_ok))
                    current_ctx = ctx_with_state(ℒ_nextctx(parse_ok), newstate)

                    push!(matched_parsers, $i)
                    found_match = true
                    #= take the first (highest priority) match that consumes input =#
                    @goto endloop_nonconsumers
                elseif is_error(result) && unwrap_error(result).consumed < 1
                    #=parser failed without consuming input, this could be an optional
                    # parser that doesn't match.
                    # mark it as matched anyway.
                    =#
                    push!(matched_parsers, $i)
                    found_match = true
                    @goto endloop_nonconsumers
                end
            end
        end)
    end

    return ex = quote
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

function parse(p::ConstrTuple{T, S}, ctx::Context{S})::InnerParseResult{S} where {T, S <: Tuple}

    _generated_tup_parse(p.parsers, ctx)

end


function complete(p::ConstrTuple{T, TState}, st::TState)::ParseResult{T} where {T, TState <: Tuple}
    out = ()
    i = 0
    @unroll 10 for parser in p.parsers
        i += 1
        result = complete(unwrapunion(parser), st[i])
        if is_error(result)
            subject = isempty(p.label) ? "tuple" : p.label
            return typedErr(T,
                error_with_context(result,
                    CompletePhase,
                    ERR_ConstrTuple,
                    subject
                )
            )
        end
        out = insert(out, IndexLens(i), unwrap(result))
    end

    return typedOk(T, out)
end
