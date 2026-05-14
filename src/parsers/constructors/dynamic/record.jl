# Dynamic (interactive) path for record parser internals.
# Uses runtime loops with @nospecialize to avoid per-tree compilation.

function _sort_obj_labels_dynamic(@nospecialize(parsers::NamedTuple))
    ks = collect(keys(parsers))
    prios = Int[priority(parsers[k]) for k in ks]
    perm = sortperm(prios; rev = true)
    return [ks[i] for i in perm]
end

function _object_parse_impl(@nospecialize(parsers::NamedTuple), @nospecialize(ctx::Context))
    sorted_keys = _sort_obj_labels_dynamic(parsers)
    S = typeof(ctx_state(ctx))

    error = ctx_hasmore(ctx) ?
        InnerParseFailure(0, constrobject_error(OBJECT_UnexpectedToken; token = ctx_peek(ctx))) :
        InnerParseFailure(0, constrobject_error(OBJECT_EndOfInput))

    anysuccess = false
    allconsumed = Consumed[consumed_empty(ctx)]

    current_ctx = ctx
    madeprogress = true
    iter = 0
    maxiter = 10000

    while madeprogress && ctx_hasmore(current_ctx) && iter < maxiter
        madeprogress = false
        iter += 1

        for field in sorted_keys
            child_parser = parsers[field]
            child_state = getproperty(ctx_state(current_ctx), field)
            child_ctx = ctx_with_state(current_ctx, child_state)

            result = parse(child_parser, child_ctx)

            if is_error(result)
                parse_err = unwrap_error(result)
                if res_num_consumed(error) < res_num_consumed(parse_err)
                    error = parse_err
                end
            else
                parse_ok = unwrap(result)

                if res_num_consumed(parse_ok) > 0
                    newstate = set(ctx_state(current_ctx), PropertyLens(field), ctx_state(res_nextctx(parse_ok)))
                    newctx = widen_restate(S, res_nextctx(parse_ok), newstate)

                    push!(allconsumed, res_consumed(parse_ok))
                    current_ctx = newctx
                    madeprogress = true
                    anysuccess = true
                    break
                end
            end
        end
    end

    if iter == maxiter
        error = InnerParseFailure(0, constrobject_error(OBJECT_MaxIter))
    end

    return current_ctx, error, allconsumed, anysuccess
end

function _object_complete_impl(@nospecialize(parsers::NamedTuple), @nospecialize(state::NamedTuple))
    T = NamedTuple{keys(parsers), Tuple{map(p -> tval(typeof(p)), values(parsers))...}}
    output = ()
    for field in keys(parsers)
        child_state = getproperty(state, field)
        child_parser = parsers[field]

        result = complete(child_parser, child_state)
        if is_error(result)
            return false, ParseResult{T}(typedErr(unwrap_error(result)))
        else
            output = (output..., unwrap(result))
        end
    end

    return true, T(output)
end
