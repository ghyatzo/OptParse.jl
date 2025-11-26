struct ConstrTuple{T, S, p, P}
    initialState::S
    parsers::P
    #
    label::String
    allowDuplicates::Bool
end

ConstrTuple(initialState, parsers::PTup, label::String, allowDuplicates::Bool) where {PTup} =
    ConstrTuple{
    Tuple{map(tval, parsers)...},
    Tuple{map(tstate, parsers)...},
    mapreduce(priority, max, parsers, init = 0),
    PTup,
}(map(p -> p.initialState, parsers), parsers, label, allowDuplicates)


function parse(p::ConstrTuple{T, S}, ctx::Context{S})::ParseResult{S, String} where {T, S}

    # Checking for duplcates will need setting up the infrastructure of automatic help
    # generation, we can have two equal options that get the same value but for different
    # reasons.

    current_ctx = ctx
    allconsumed::Tuple{Vararg{String}} = ()
    matched_parsers = Set()

    # instead of sorting each time:
    # 	- calculate the sortpermutation by priority
    #	- each time we have a match remove the matching item in the permutation
    #	-
    while length(matched_parsers) < length(p.parsers)
        found_match = false

        error = (0, "No remaining parsers could match the input")

        #use same trick as object
        perm = sortperm(collect(); by = priority, rev = true)
        filter_perm = filter(already in matched_parsers)
        remaining_parsers = p.parsers[filter_perm]

        i = 1
        for parser in remaining_parsers
            result = parse(parser, current_ctx.state[filter_perm[i]])

            if !is_error(result) && length(unwrap(result).consumed) > 0
                parse_ok = unwrap(result)

                newctx = Context(
                    parse_ok.next.buffer,
                    @set current_ctx.state[filter_perm[i]] = parse_ok.next.state,
                        parse_ok.next.optionsTerminated
                )

                allconsumed = (allconsumed..., parse_ok.consumed...)
                push!(matched_parsers, i)
                found_match = true
                break # take the first (highest priority) match that consumes input
            elseif is_error(result) && error[1] <= unwrap_error(result).consumed
                parse_err = unwrap_error(result)
                error = (parse_err.consumed, parse_err.error)
            end

            # if no consuming parser is matched, try non consuming ones (like optional or constant)
            if !found_match
                # same thing but with a quirk...
            end
        end
    end
    return
end
