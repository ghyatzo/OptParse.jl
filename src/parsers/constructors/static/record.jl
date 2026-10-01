# Static (juliac/trim) path for record parser internals.
# Uses @generated functions for fully unrolled, type-stable code.

@generated function _object_parse_impl(p::NamedTuple{labels, PTup}, ctx::Context{S}) where {labels, PTup <: Tuple, S}

    sorted_labels = _sort_obj_labels(labels, PTup)
    whilebody = Expr(:block)
    E = reduce(joinerr, map(p -> err_t(p), fieldtypes(PTup)), init = ConstrObjectError)

    for field in sorted_labels
        push!(
            whilebody.args, quote
                child_parser = p[$(QuoteNode(field))]
                child_state = getproperty(state(current_ctx), $(QuoteNode(field)))
                child_ctx = widen_restate(state_t(child_parser), current_ctx, child_state)

                result = (parse(child_parser, child_ctx))::InnerResult{state_t(child_parser)}

                if is_error(result)
                    parse_err = unwrap_error(result)
                    if res_num_consumed(error) < res_num_consumed(parse_err)
                        error = InnerFailure{$E}(parse_err.consumed, parse_err.error)
                    end
                else
                    parse_ok = unwrap(result)


                    if res_num_consumed(parse_ok) > 0

                        #= we update the current context state with the result from the parse=#
                        newstate = set(state(current_ctx), PropertyLens($(QuoteNode(field))), res_nextstate(parse_ok))

                        #= then we continue the parse using the information from the parse result but with the new state=#
                        newctx = widen_restate($S, res_nextctx(parse_ok), newstate)

                        push!(allconsumed, res_consumed(parse_ok))
                        current_ctx = newctx
                        madeprogress = true
                        anysuccess = true

                        #=
                        We manually insert gotos to emulate a break within an unrolled for loop inside a while loop
                        =#
                        @goto startwhile
                    end
                end
            end
        )
    end

    return quote
        #= if nothing inside the record can match our token, then it's "unexpected" =#
        error = InnerFailure{$E}(0,
               hasmore(ctx) ?
                   ConstrObjectError(OBJECT_UnexpectedToken, peek(ctx)) :
                   ConstrObjectError(OBJECT_EndOfInput, "")
           )
        #= greedy parsing trying to consume as many field as possible =#
        anysuccess = false
        allconsumed = Consumed[consumed_empty(ctx)]

        #= keep trying to parse fields until no more can be matched =#
        current_ctx = ctx
        madeprogress = true
        iter = 0
        maxiter = 10000 # avoids infinite loops (mainly useful while debugging.)
        @label startwhile
        while (madeprogress && hasmore(current_ctx) > 0) && iter < maxiter
            madeprogress = false
            iter += 1

            $whilebody
        end

        if iter == maxiter
            error = InnerFailure(0, ConstrObjectError(OBJECT_MaxIter, ""))
        end

        return current_ctx, error, allconsumed, anysuccess
    end
end

@generated function _object_can_complete(p::NamedTuple{labels, PTup}, state::NamedTuple{labels, STup}) where {labels, PTup, STup}
    Ps = PTup.parameters
    Ss = STup.parameters

    ex = Expr(:block)
    for (i, field) in enumerate(labels)
        S = Ss[i]
        push!(
            ex.args, quote
                child_state = state[$(QuoteNode(field))]::$S
                child_parser = p[$(QuoteNode(field))]
                result = complete(child_parser, child_state)
                is_error(result) && return false
            end
        )
    end
    push!(ex.args, :(return true))
    return ex
end

@generated function _object_complete_impl(p::NamedTuple{labels, PTup}, state::NamedTuple{labels, STup}) where {labels, PTup, STup}
    Ps = PTup.parameters
    Ss = STup.parameters
    T = NamedTuple{labels, Tuple{map(val_t, Ps)...}}
    E = reduce(joinerr, map(err_t, Ps), init = ConstrObjectError)

    ex = Expr(:block)

    # Phase 1: complete each child into a typed local, early-return on error
    for (i, field) in enumerate(labels)
        S = Ss[i]
        result_sym = Symbol("result_", i)
        push!(
            ex.args, quote
                child_state = state[$(QuoteNode(field))]::$S
                child_parser = p[$(QuoteNode(field))]
                $result_sym = complete(child_parser, child_state)
                is_error($result_sym) && return Result{$T, $E}'.Err(unwrap_error($result_sym))
            end
        )
    end

    # Phase 2: construct the NamedTuple from all successful results
    unwraps = [:(unwrap($(Symbol("result_", i)))::$(val_t(Ps[i]))) for i in eachindex(Ps)]
    push!(ex.args, :(return Result{$T, $E}'.Ok($T(($(unwraps...),)))))

    return ex
end

@generated function _object_helpentries_impl(parsers::PObj, rt::OverlayContext) where {PObj <: NamedTuple}
    ex = quote
        entries = HelpEntry[]
    end
    for (i, type) in enumerate(fieldtypes(PObj))
        push!(
            ex.args,
            :(append!(entries, helpentries(parsers[$i], descend_child(rt))::Vector{HelpEntry}))
        )
    end
    push!(ex.args, :(return entries))
    return ex
end

@generated function _focused_helpdoc_object(
        p::ConstrObject{T, <:Any, S, PTup},
        ctx::Context{S},
        prefix::Vector{String},
        rt::OverlayContext
    ) where {T, PTup <: NamedTuple, S <: ObjectState}
    N = fieldcount(PTup)
    body = Expr(:block)

    for i in 1:N
        child_state_t = fieldtype(S, i)
        push!(
            body.args, quote
                child_state = state(ctx)[$i]::$child_state_t
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
