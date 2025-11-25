const OptionalState{X} = Option{X}

struct ModOptional{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    parser::P

    ModOptional(parser::P) where {P} =
        new{Union{Nothing, tval(P)}, OptionalState{tstate(P)}, priority(P), P}(none(tstate(P)), parser)
end


function parse(p::ModOptional{T, OptionalState{S}}, ctx::Context{OptionalState{S}})::ParseResult{OptionalState{S}, String} where {T, S}

    childstate = isnothing(base(ctx.state)) ? p.parser.initialState : @something base(ctx.state)
    childctx = @set ctx.state = childstate
    result = parse(unwrapunion(p.parser), childctx)::ParseResult{S, String}

    if !is_error(result)
        parse_ok = unwrap(result)
        newctx = set(parse_ok.next, PropertyLens(:state), some(parse_ok.next.state))
        return ParseOk(parse_ok.consumed, newctx)
    else
        return Err(unwrap_error(result))
    end
end

function complete(p::ModOptional{T, OptionalState{S}, _p, P}, maybestate::OptionalState{S})::Result{T, String} where {T, S, _p, P}
    state = base(maybestate) # collapses the optional to a nothing or a Some
    isnothing(state) && return Ok(nothing)

    result = complete(unwrapunion(p.parser), something(state))::Result{tval(P), String}

    if !is_error(result)
        return Ok(unwrap(result))
    else
        # it's a bit stupid, but conceptually makes sense:
        # result is of type Result{T, String}
        # we need to return a Result{Option{T}, String}
        # so we unwrap and rewrap with the correct type.
        # in the future will probably deal with this with a convert acting on a more comprehensive error system.
        return Err(unwrap_error(result))
    end

end
