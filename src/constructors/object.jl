const ObjectState{L, P} = NamedTuple{L, P}

struct Object{T, S, p, P}
    initialState::S # NamedTuple of the states of its parsers
    #
    parsers::P
    label::String
end

Object{T}(priority, initialState::TState, parsers, label) where {T, TState} =
    Object{T, TState, priority, typeof(parsers)}(initialState, parsers, label)

#=
	This is does the same thing but in a different way.
	The difference is that the generated function approach
	stresses the compiler more. And deals with an AST instead of an actual value
=#
# @generated function gen_sorted_obj(nt::NamedTuple{labels, parsers_t_tup}) where {labels, parsers_t_tup}
# 	parsers_t = collect(parsers_t_tup.parameters)
# 	perm = sortperm(parsers_t; by=priority, rev=true)
# 	slabels = labels[perm]
# 	:(nt[$slabels])
# end

#=
	we're using @assume_effects :foldable in order to tell julia that
	this function is actually allowed to be constant-folded!
	(from Mason Protter, black magic)
=#
Base.@assume_effects :foldable function _sort_obj_labels(
        labels, ::Type{parsers_t_tup}
    ) where {parsers_t_tup <: Tuple}
    perm = sortperm(collect(parsers_t_tup.parameters); by = priority, rev = true)
    return labels[perm]
end

function _sort_obj(
        obj::NamedTuple{labels, parsers_t_tup}
    ) where {labels, parsers_t_tup <: Tuple}
    slabels = _sort_obj_labels(labels, parsers_t_tup)
    return obj[slabels]
end

_object(obj::NamedTuple; label = "") = let

    sobj = _sort_obj(obj)
    labels = keys(sobj)
    parsers_t = fieldtypes(typeof(sobj))
    parsers = values(sobj)
    parsers_tvals = map(tval, parsers_t)
    parsers_tstates = map(tstate, parsers_t)
    priorities = map(priority, parsers_t)

    obj_t = NamedTuple{labels, Tuple{parsers_tvals...}}
    init_state = NamedTuple{labels}(map(p -> getproperty(p, :initialState), parsers))

    Object{obj_t}(maximum(priorities), init_state, sobj, label)
end

#= this works! we can attempt some kind of recursion... although, yikes =#
# function test(t::NamedTuple{labels, Tup}, cx::NamedTuple) where {labels, Tup}
# 	_test(labels, cx, values(t))
# end

# @inline function _test(labels, cx, v)
# 	cx = _test(Base.tail(labels), cx, Base.tail(v))
# 	set(cx, PropertyLens(first(labels)), first(v))
# end
# _test(::Tuple{}, cx, v) = cx
# _test(a, cx, ::Tuple{}) = cx

# @inline _recursive_parse_parsers(::@NamedTuple{}, ctx, error, all_consumed, anysuccess) =
#     return ctx, error, all_consumed, false, anysuccess

# @inline _recursive_parse_parsers(p::NamedTuple{labels}, ctx, error, all_consumed, anysuccess) where {labels} = let
#     Base.@assume_effects :foldable
#     # Main.@infiltrate
#     field = first(labels)
#     child_state = ctx.state[field]
#     child_parser = p[field]

#     child_ctx = @set ctx.state = child_state

#     result = parse(child_parser, child_ctx)::ParseResult{typeof(child_state), String}

#     if is_error(result)
#         parse_err = unwrap_error(result)
#         if error.consumed <= parse_err.consumed
#             error = parse_err
#         end
#     else
#         parse_ok = unwrap(result)
#         if length(parse_ok.consumed) > 0
#             newstate = set(ctx.state, PropertyLens(field), parse_ok.next.state)

#             newctx = Context(
#                 parse_ok.next.buffer,
#                 newstate,
#                 ctx.optionsTerminated
#             )

#             all_consumed = (all_consumed..., parse_ok.consumed...)

#             return newctx, error, all_consumed, true, true
#         end
#     end

#     return _recursive_parse_parsers(Base.tail(p), ctx, error, all_consumed, anysuccess)
# end

@generated function _generated_parse_parsers(p::NamedTuple{labels}, ctx::Context) where {labels}


    whilebody = Expr(:block)

    for field in labels
        push!(
            whilebody.args, quote
                field = $(QuoteNode(field))
                child_state = current_ctx.state[$(QuoteNode(field))]
                child_parser = p[$(QuoteNode(field))]
                child_ctx = @set current_ctx.state = child_state

                result = parse(child_parser, child_ctx)::ParseResult{typeof(child_state), String}

                if is_error(result)
                    parse_err = unwrap_error(result)
                    if error.consumed <= parse_err.consumed
                        error = parse_err
                    end
                    # Main.@infiltrate
                else
                    parse_ok = unwrap(result)
                    if length(parse_ok.consumed) > 0
                        newstate = set(current_ctx.state, PropertyLens($(QuoteNode(field))), parse_ok.next.state)

                        newctx = set(parse_ok.next, PropertyLens(:state), newstate)

                        allconsumed = (allconsumed..., parse_ok.consumed...)
                        current_ctx = newctx
                        madeprogress = true
                        anysuccess = true
                        # Main.@infiltrate
                        @goto startwhile
                    end
                end
            end
        )
    end

    return ex = quote
        error = ParseFailure(0, "Expected argument, option or command, but got end of input.")

        #= greedy parsing trying to consume as many field as possible =#
        anysuccess = false
        allconsumed::Tuple{Vararg{String}} = ()

        #= keep trying to parse fields until no more can be matched =#
        current_ctx = ctx
        madeprogress = true
        iter = 0
        maxiter = 10000 # avoids infinite loops
        @label startwhile
        while (madeprogress && length(current_ctx.buffer) > 0) && iter < maxiter
            madeprogress = false

            $whilebody
            iter += 1
        end

        return current_ctx, error, allconsumed, anysuccess
    end
end

function parse(p::Object{NamedTuple{fields, Tup}, S}, ctx::Context)::ParseResult{S, String} where {fields, Tup, S}
    # @show _generated_parse_parsers(p.parsers, ctx)

    outctx, error, allconsumed, anysuccess = _generated_parse_parsers(p.parsers, ctx)

    if anysuccess
        return ParseOk(
            allconsumed,
            outctx
        )
    end

    #= if buffer is empty check if all parsers can complete anyway =#
    if length(ctx.buffer) == 0
        all_can_complete, _ = _generated_complete_parsers(p.parsers, ctx.state)

        if all_can_complete
            return ParseOk((), ctx)
        end
    end

    return Err(error)
end

# function _parse(p::Object{NamedTuple{fields, Tup}, S}, ctx::Context)::ParseResult{S, String} where {fields, Tup, S}
#     error = ParseFailure(0, "Expected argument, option or command, but got end of input.")

#     #= greedy parsing trying to consume as many field as possible =#
#     anysuccess = false
#     allconsumed::Tuple{Vararg{String}} = ()

#     #= keep trying to parse fields until no more can be matched =#
#     current_ctx = ctx
#     made_progress = true
#     while (made_progress && length(current_ctx.buffer) > 0)
#         # @infiltrate
#         current_ctx, error, allconsumed, made_progress, anysuccess = _recursive_parse_parsers(p.parsers, current_ctx, error, allconsumed, anysuccess)
#     end


#     if anysuccess
#         return ParseOk(
#             allconsumed,
#             current_ctx
#         )
#     end

#     #= if buffer is empty check if all parsers can complete anyway =#
#     if length(ctx.buffer) == 0
#         all_can_complete, _ = _recursive_complete_parsers(p.parsers, ctx.state, (;))

#         if all_can_complete
#             return ParseOk((), ctx)
#         end
#     end

#     return Err(error)
# end


# @inline _recursive_complete_parsers(::@NamedTuple{}, _, output::NamedTuple) =
#     true, output
# @inline _recursive_complete_parsers(p::NamedTuple{labels}, state, output::NamedTuple) where {labels} = let
#     Base.@assume_effects :foldable

#     field = first(labels)
#     child_state = state[field]
#     child_parser = p[field]

#     result = complete(child_parser, child_state)::Result{tval(typeof(child_parser)), String}

#     if is_error(result)
#         return false, result
#     else
#         output = insert(output, PropertyLens(field), unwrap(result))
#         return _recursive_complete_parsers(Base.tail(p), state, output)
#     end
# end

@generated function _generated_complete_parsers(p::NamedTuple{labels, PTup}, state::NamedTuple{labels, STup}) where {labels, PTup, STup}
    pre = :(output = (;))

    ex = Expr(:block)
    Ps = PTup.parameters
    Ss = STup.parameters
    i = 1
    for field in labels
        T = tval(Ps[i])

        push!(
            ex.args, quote
                child_state = state[$(QuoteNode(field))]
                child_parser = p[$(QuoteNode(field))]

                result = complete(child_parser, child_state)::Result{$T, String}
                if is_error(result)
                    return false, result
                else
                    output = insert(output, PropertyLens($(QuoteNode(field))), unwrap(result))
                end
            end
        )
        i += 1
    end

    post = :(return true, output)
    return quote
        $pre
        $ex
        $post
    end
end


function complete(p::Object{T}, st::NamedTuple)::Result{T, String} where {T}

    cancomplete, _result = _generated_complete_parsers(p.parsers, st)

    if !cancomplete
        return Err(unwrap_error(_result))
    end

    return Ok(_result)
end
