struct ModOptional{T, S, p, P}
    initialState::S
    parser::P

    ModOptional(parser::P) where {P} =
        new{Option{tval(P)}, tstate(P), priority(P), P}(parser.initialState, parser)
end


function parse(p::ModOptional{T, S}, ctx::Context)::ParseResult{S, String} where {T, S}
    result = parse(p.parser, ctx)::ParseResult{S, String}

    if !is_error(result)
        parse_ok = unwrap(result)
        return ParseOk(parse_ok.consumed, parse_ok.next)
    else
        newctx = (@set ctx.state = S(Err(unwrap_error(result).error)))
        return ParseOk(String[], newctx)
    end
end

function complete(p::ModOptional{T, S, _p, P}, st::S)::Result{T, String} where {T, S, _p, P}
    is_error(st) && return Ok(none(tval(P)))

    result = complete(p.parser, st)::Result{tval(P), String}

    if !is_error(result)
        return Ok(some(unwrap(result)))
    else
        return Err(unwrap_error(result))
    end

end
