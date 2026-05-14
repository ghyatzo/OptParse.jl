# Dynamic (interactive) path for tuple parser internals.
# Uses runtime loops with @nospecialize to avoid per-tree compilation.

function _sort_tup_by_priority(@nospecialize(parsers::Tuple))
    N = length(parsers)
    prios = Int[priority(parsers[i]) for i in 1:N]
    return sortperm(prios; rev = true)
end

function _tup_parse_impl(@nospecialize(parsers::Tuple), @nospecialize(ctx::Context))
    N = length(parsers)
    perm = _sort_tup_by_priority(parsers)

    current_ctx = ctx
    allconsumed = Consumed[consumed_empty(ctx)]
    matched_parsers = Set{Int}()

    while length(matched_parsers) < N
        found_match = false

        error = InnerParseFailure(
            0,
            constrtuple_error(
                TUPLE_NoRemainingParser;
                token = ctx_hasmore(current_ctx) ? ctx_peek(current_ctx) : "",
            )
        )

        # Pass 1: try consuming parsers in priority order
        for sorted_i in 1:N
            sorted_i ∈ matched_parsers && continue
            orig_i = perm[sorted_i]

            parser = parsers[orig_i]
            child_state = ctx_state(current_ctx)[orig_i]
            child_ctx = ctx_with_state(current_ctx, child_state)

            result = parse(parser, child_ctx)

            if !is_error(result) && length(unwrap(result).consumed) > 0
                parse_ok = unwrap(result)

                if parse_ok.counts_as_match
                    newstate = set(ctx_state(current_ctx), IndexLens(orig_i), ctx_state(res_nextctx(parse_ok)))
                    current_ctx = ctx_with_state(res_nextctx(parse_ok), newstate)

                    push!(allconsumed, res_consumed(parse_ok))
                    push!(matched_parsers, sorted_i)
                    found_match = true
                    break
                else
                    current_ctx = ctx_with_state(res_nextctx(parse_ok), ctx_state(current_ctx))
                    push!(allconsumed, res_consumed(parse_ok))
                end
            elseif is_error(result) && res_num_consumed(error) < res_num_consumed(result)
                error = unwrap_error(result)
            end
        end

        # Pass 2: if no consuming parser matched, try non-consuming ones
        if !found_match
            for sorted_i in 1:N
                sorted_i ∈ matched_parsers && continue
                orig_i = perm[sorted_i]

                parser = parsers[orig_i]
                child_state = ctx_state(current_ctx)[orig_i]
                child_ctx = ctx_with_state(current_ctx, child_state)

                result = parse(parser, child_ctx)

                if !is_error(result) && length(unwrap(result).consumed) < 1
                    parse_ok = unwrap(result)
                    newstate = set(ctx_state(current_ctx), IndexLens(orig_i), ctx_state(res_nextctx(parse_ok)))
                    current_ctx = ctx_with_state(res_nextctx(parse_ok), newstate)

                    push!(matched_parsers, sorted_i)
                    found_match = true
                    break
                elseif is_error(result) && res_num_consumed(result) < 1
                    push!(matched_parsers, sorted_i)
                    found_match = true
                    break
                end
            end
        end

        if !found_match
            return innerErr(current_ctx, error)
        end
    end

    mergedcons = merge(allconsumed)
    return innerOk(current_ctx, mergedcons)
end

function _tuple_complete_impl(@nospecialize(parsers::Tuple), @nospecialize(state::Tuple))
    T = Tuple{map(p -> tval(typeof(p)), parsers)...}
    output = ()
    for i in eachindex(parsers)
        child_state = state[i]
        child_parser = parsers[i]

        result = complete(child_parser, child_state)
        if is_error(result)
            return false, ParseResult{T}(typedErr(unwrap_error(result)))
        end

        output = (output..., unwrap(result))
    end

    return true, output::T
end

function _tuple_helpentries_impl(@nospecialize(parsers::Tuple), rt::OverlayContext)
    entries = HelpEntry[]
    for child in parsers
        append!(entries, helpentries(child, descend_child(rt))::Vector{HelpEntry})
    end
    return entries
end

function _focused_helpdoc_tuple(
        @nospecialize(p::ConstrTuple), @nospecialize(ctx::Context),
        prefix::Vector{String}, rt::OverlayContext
    )
    entries = HelpEntry[]
    parsers = p.parsers
    state = ctx_state(ctx)
    for i in 1:length(parsers)
        child_state = state[i]
        child_ctx = widen_restate(typeof(child_state), ctx, child_state)
        child_helpdoc = focused_helpdoc(parsers[i], child_ctx, prefix, descend_child(rt))::HelpDoc

        if child_helpdoc.prefix != prefix
            return child_helpdoc
        end

        append!(entries, helpentries(parsers[i], descend_child(rt))::Vector{HelpEntry})
    end
    return HelpDoc(prefix, usage(p), helpinfo(rt), entries)
end
