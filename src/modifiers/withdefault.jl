const WithDefaultState{X} = Option{X}

struct ModWithDefault{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    parser::P
    #
    default::T

    ModWithDefault(parser::P, default::T) where {T, P} = let
        new{tval(P), WithDefaultState{tstate(P)}, priority(P), P}(none(tstate(P)), parser, default)
    end
end

function parse(p::ModWithDefault{T, WithDefaultState{S}}, ctx::Context{WithDefaultState{S}})::ParseResult{WithDefaultState{S}, String} where {T, S}

    childstate = isnothing(base(ctx.state)) ? p.parser.initialState : @something base(ctx.state)
    childctx = @set ctx.state = childstate
    result = parse(p.parser, childctx)::ParseResult{S, String}

    if !is_error(result)
        parse_ok = unwrap(result)
        newctx = set(parse_ok.next, PropertyLens(:state), some(parse_ok.next.state))
        return ParseOk(parse_ok.consumed, newctx)
    else
        parse_err = unwrap_error(result)
        return ParseErr(parse_err.consumed, parse_err.error)
    end
end

function complete(p::ModWithDefault{T, WithDefaultState{S}}, maybestate::WithDefaultState{S})::Result{T, String} where {T, S}
    state = base(maybestate)
    isnothing(state) && return Ok(p.default)

    # here we can return directly since tval(ModWithDefault) == tval(inner parser)
    return complete(p.parser, something(state))::Result{T, String}
end
