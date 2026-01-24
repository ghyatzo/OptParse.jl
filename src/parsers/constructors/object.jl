const ObjectState{L, P} = NamedTuple{L, P}

struct ConstrObject{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S # NamedTuple of the states of its parsers
    #
    parsers::P
    label::String
end

ConstrObject{T}(initialState::TState, parsers, label) where {T, TState} =
    ConstrObject{
        T,
        TState,
        mapreduce(p -> priority(p), max, parsers),
        typeof(parsers)
    }(initialState, parsers, label)

#=
    This is does the same thing but in a different way.
    The difference is that the generated function approach
    stresses the compiler more. And deals with an AST instead of an actual value

    # @generated function gen_sorted_obj(nt::NamedTuple{labels, PTup}) where {labels, PTup}
    #   parsers_t = collect(PTup.parameters)
    #   perm = sortperm(parsers_t; by=priority, rev=true)
    #   slabels = labels[perm]
    #   :(nt[$slabels])
    # end

    we're using @assume_effects :foldable in order to tell julia that
    this function is actually allowed to be constant-folded!
    (from Mason Protter, black magic)
=#
Base.@assume_effects :foldable function _sort_obj_labels(
        labels, ::Type{PTup}
    ) where {PTup <: Tuple}

    perm = sortperm(collect(fieldtypes(PTup)); by = priority, rev = true)
    return labels[perm]
end

function _sort_obj(obj::NamedTuple{labels, PTup}) where {labels, PTup <: Tuple}
    slabels = _sort_obj_labels(labels, PTup)
    return obj[slabels]
end

_object(parsers_obj::NamedTuple; label = "") =
let
    sparsers_obj = _sort_obj(parsers_obj)
    labels = keys(sparsers_obj)
    parsers_t = fieldtypes(typeof(sparsers_obj))
    parsers = values(sparsers_obj)
    parsers_tvals = map(tval, parsers_t)
    parsers_tstates = map(tstate, parsers_t)

    parsers_obj_tval = NamedTuple{labels, Tuple{parsers_tvals...}}
    init_state = NamedTuple{labels, Tuple{parsers_tstates...}}(map(p -> p.initialState, parsers))

    ConstrObject{parsers_obj_tval}(init_state, sparsers_obj, label)
end


@generated function _generated_object_parse(p::NamedTuple{labels}, ctx::Context{S}) where {labels, S}


    whilebody = Expr(:block)

    for field in labels
        push!(
            whilebody.args, quote
                child_state_lens = PropertyLens($(QuoteNode(field))) ∘ ℒ_state

                child_parser = p[$(QuoteNode(field))]
                child_state = child_state_lens(current_ctx)
                child_ctx = widen_restate(tstate(child_parser), current_ctx, child_state)

                result = (@unionsplit parse(child_parser, child_ctx))::ParseResult{tstate(child_parser), String}

                if is_error(result)
                    parse_err = unwrap_error(result)
                    if ℒ_nconsumed(error) < ℒ_nconsumed(parse_err)
                        error = parse_err
                    end
                else
                    parse_ok = unwrap(result)


                    if length(ℒ_consumed(parse_ok)) > 0

                        #= we update the current context state with the result from the parse=#
                        newstate = set(ℒ_state(current_ctx), PropertyLens($(QuoteNode(field))), ℒ_nextstate(parse_ok))

                        #= then we continue the parse using the information from the parse result but with the new state=#
                        newctx = widen_restate($S, ℒ_nextctx(parse_ok), newstate)

                        push!(allconsumed, ℒ_consumed(parse_ok))
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

    return ex = quote
        #= if nothing inside the object can match our token, then it's "unexpected" =#
        error = ctx_hasmore(ctx) > 0 ? ParseFailure(0, "Unexpected option or argument: `$(ctx_peek(ctx))`") :
            ParseFailure(0, "Expected option or argument, got end of input.")
        #= greedy parsing trying to consume as many field as possible =#
        anysuccess = false
        allconsumed = Consumed[consumed_empty(ctx)]

        #= keep trying to parse fields until no more can be matched =#
        current_ctx = ctx
        madeprogress = true
        iter = 0
        maxiter = 10000 # avoids infinite loops (mainly useful while debugging.)
        @label startwhile
        while (madeprogress && ctx_hasmore(current_ctx) > 0) && iter < maxiter
            madeprogress = false
            iter += 1

            $whilebody
        end

        if iter == maxiter
            println(Core.stderr, "[DEBUG] Max iteration reached!")
        end

        return current_ctx, error, allconsumed, anysuccess
    end
end

function parse(p::ConstrObject{NamedTuple{fields, Tup}, S}, ctx::Context)::ParseResult{S, String} where {fields, Tup, S}

    # TODO: check for duplicates

    outctx, error, allconsumed, anysuccess = _generated_object_parse(p.parsers, ctx)

    #= we must coalesce all the consumed tokens into a single Consumed object =#
    mergedcons = merge(allconsumed)

    # TODO: continue.
    if anysuccess
        return parseok(outctx, mergedcons)
    end

    #= if buffer is empty check if all parsers can complete anyway =#
    if ctx_hasnone(ctx) == 0
        all_can_complete, _ = _generated_object_complete(p.parsers, ℒ_state(ctx))

        if all_can_complete
            return parseok(ctx, consumed_empty(ctx))
        end
    end

    return parseerr(error)
end

@generated function _generated_object_complete(p::NamedTuple{labels, PTup}, state::NamedTuple{labels, STup}) where {labels, PTup, STup}
    pre = :(output = (;))

    ex = Expr(:block)
    Ps = PTup.parameters
    Ss = STup.parameters
    T = NamedTuple{labels, Tuple{map(tval, Ps)...}}
    i = 1
    for field in labels
        Ti = tval(Ps[i])
        S = Ss[i]
        push!(
            ex.args, quote
                child_state = state[$(QuoteNode(field))]::$S
                child_parser = p[$(QuoteNode(field))]

                result = (@unionsplit complete(child_parser, child_state))::Result{$Ti, String}
                if is_error(result)
                    return false, Result{$T, String}(Err(unwrap_error(result)))
                else
                    output = (output..., unwrap(result))
                end
            end
        )
        i += 1
    end

    post = :(return true, $T(output))
    return quote
        $pre
        $ex
        $post
    end
end


function complete(p::ConstrObject{T}, st::NamedTuple)::Result{T, String} where {T}

    cancomplete, _result = _generated_object_complete(p.parsers, st)

    if !cancomplete
        return Err(unwrap_error(_result))
    end

    return Ok(_result)
end



# # object parser return a named tuple, that can be tagged by a @constant value ie (tag=Val(:some_action), value=10, ...)
# # we can dispatch on that tag like so:

# const Tagged{tag} = NamedTuple{N, <: Tuple{Val{tag}, Vararg}} where {N}
# f(nt::Tagged{:a}) = "this is tagged as :a"
# f(nt::Tagged{:b}) = "this is tagged as :b"

