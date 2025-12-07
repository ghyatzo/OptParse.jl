const WithDefaultState{X} = Option{X}

struct ModWithDefault{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    parser::P
    #
    default::T

    ModWithDefault(parser::P, default::T) where {T, P} = let
        retval_t = tval(P) == T ? T : Union{tval(P), T}
        new{retval_t, WithDefaultState{tstate(P)}, priority(P), P}(none(tstate(P)), parser, default)
    end
end

function parse(p::ModWithDefault{T, WithDefaultState{S}}, ctx::Context{WithDefaultState{S}})::ParseResult{WithDefaultState{S}, String} where {T, S}

    childstate = is_error(ctx.state) ? p.parser.initialState : unwrap(ctx.state)
    childctx = @set ctx.state = childstate
    result = parse(unwrapunion(p.parser), childctx)::ParseResult{S, String}

    if is_error(result)
        parse_err = unwrap_error(result)
        #=the inner parser failed without consuming any input, which means that it wasn't matched.=#
        if parse_err.consumed == 0
            return ParseOk((), ctx)
        else
            #=otherwise the parser failed midway, and that we should propagate.=#
            return Err(parse_err)
        end
    end

    parse_ok = unwrap(result)
    if parse_ok.next.state != childstate || length(parse_ok.consumed) == 0
        #=Inner parser actually consumed something or changed its state=#
        newctx = set(parse_ok.next, PropertyLens(:state), some(parse_ok.next.state))
    else
        #=Inner parser returned success but nothing changed while consuming input. (i.e. "--")
        Treat as unmatched, but still propagate side effects.=#
        newctx = set(parse_ok.next, PropertyLens(:state), ctx.state)
    end

    return ParseOk(parse_ok.consumed, newctx)

end

function complete(p::ModWithDefault{T, WithDefaultState{S}}, maybestate::WithDefaultState{S})::Result{T, String} where {T, S}

    #= The state can be missing (none), in which case simply return the result. =#
    state = @unwrap_or maybestate (return Ok(p.default))


    #=This approach would also work, but is less conceptually correct. We're assuming that a state is a Result.
    This may lead to further headaches in the future. Instead we catch this case at parse time. (see if else on success)=#
    # The state exists but is an error.
    #state isa Result && is_error(state) && return Ok(p.default)

    #= Otherwise just ask the inner state to complete itself.
    In case of validation errors from the value parser, we want to return an error instead of the default.
    Given that the user explicitly passed a value, he likely does not want the default value.=#
    result = complete(unwrapunion(p.parser), state)::Result{tval(p.parser), String}


    # we need to rewrap so that in case of a union it is properly rendered.
    return Ok(@? result)
end
