struct ConstrTuple{T, S, p, P}
    initialState::S
    parsers::P
    #
    label::String
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


function parse(p::ConstrTuple{T, S}, ctx::Context{S})::ParseResult{S, String} where {T, S <: Tuple}

    # TODO: Checking for duplcates will need setting up the infrastructure of automatic help
    # generation, we can have two equal options that get the same value but for different
    # reasons.

    current_ctx = ctx
    allconsumed::Tuple{Vararg{String}} = ()
    matched_parsers = Set{Int}()

    # instead of sorting each time:
    # 	- calculate the sortpermutation by priority
    #	- each time we have a match remove the matching item in the permutation

    #= match the parsers in priority order but maintain tuple order =#
    perm, sorted_ptup = _sortperm_by_priority(p.parsers)

    while length(matched_parsers) < length(p.parsers)
        found_match = false

        error = (0, "No remaining parsers could match the input.")

        #= instead of filtering by the already matched parsers
        # we iterate over all parsers and skip those already matched.
        # this way we know which parser we're working with at compile time.
        # less efficient computationally but at least type stable
        =#
        i = 0
        # TODO: switch to a generated function to unroll based on the length of the tuple without random ass magic numbers
        @unroll 10 for parser in sorted_ptup
            i += 1
            #= we need to simulate a i in matched_parsers && continue but in an unrolled loop
            # so it becomes a whole if, this unrolled part only happens if it's not yet matched!
            =#
            if i ∉ matched_parsers
                # @info current_ctx.state perm[i] current_ctx.state[perm[i]]
                child_ctx = Context{tstate(parser)}(
                    current_ctx.buffer,
                    current_ctx.state[perm[i]],
                    current_ctx.optionsTerminated
                )

                result = parse(unwrapunion(parser), child_ctx)::ParseResult{tstate(parser), String}

                if !is_error(result) && length(unwrap(result).consumed) > 0
                    #= parser succeded and consumed input - match it =#
                    parse_ok = unwrap(result)

                    current_ctx = Context{S}(
                        parse_ok.next.buffer,
                        set(current_ctx.state, IndexLens(perm[i]), parse_ok.next.state),
                        parse_ok.next.optionsTerminated
                    )

                    allconsumed = (allconsumed..., parse_ok.consumed...)
                    push!(matched_parsers, i)
                    found_match = true
                    #= take the first (highest priority) match that consumes input =#
                    @goto endloop_consumers #= it simulates a "break" by using @goto.
                    # tecnically the @unroll macro also already uses a "loopend" label, but It seems that
                    # these goto macros are expanded before the @unroll and therefore is not there yet. =#
                elseif is_error(result) && error[1] < unwrap_error(result).consumed
                    parse_err = unwrap_error(result)
                    error = (parse_err.consumed, parse_err.error)
                end
            end
        end
        @label endloop_consumers


        #=if no consuming parser is matched, try non consuming ones (like optional or constant)=#
        if !found_match
            i = 0
            @unroll 10 for parser in sorted_ptup
                i += 1
                if i ∉ matched_parsers

                    child_ctx = Context{tstate(parser)}(
                        current_ctx.buffer,
                        current_ctx.state[perm[i]],
                        current_ctx.optionsTerminated
                    )

                    result = parse(unwrapunion(parser), child_ctx)::ParseResult{tstate(parser), String}

                    if !is_error(result) && length(unwrap(result).consumed) < 1
                        #=parser succeded without consuming - match it as success=#
                        parse_ok = unwrap(result)

                        current_ctx = Context{S}(
                            parse_ok.next.buffer,
                            set(current_ctx.state, IndexLens(perm[i]), parse_ok.next.state),
                            parse_ok.next.optionsTerminated
                        )

                        push!(matched_parsers, i)
                        found_match = true
                        @goto endloop_nonconsumers
                    elseif is_error(result) && unwrap_error(result).consumed < 1
                        #=parser failed without consuming input, this could be an optional
                    	# parser that doesn't match.
                    	# mark it as matched anyway.
                    	=#
                        push!(matched_parsers, i)
                        found_match = true
                        @goto endloop_nonconsumers
                    end
                end
            end
            @label endloop_nonconsumers
        end

        if !found_match
            #=If we still haven't found a match then cry=#
            return Err(error[1], error[2])
        end
    end

    return ParseOk(allconsumed, current_ctx)
end


function complete(p::ConstrTuple{T, TState}, st::TState)::Result{T, String} where {T, TState <: Tuple}
    out = ()
    i = 0
    @unroll 10 for parser in p.parsers
        i += 1
        result = complete(unwrapunion(parser), st[i])
        out = insert(out, IndexLens(i), @? result)
    end

    return Ok(out)
end
