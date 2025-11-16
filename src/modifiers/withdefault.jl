struct ModWithDefault{T, S, p, P}
    initialState::S
    parser::P
    #
    default::T

    ModWithDefault(parser::P, default::T) where {P, T} = let
        if tval(P) != T
            error("Expected default of type $(tval(P)), got $T")
        end
        new{T, tstate(P), priority(P), P}(parser.initialState, parser, default)
    end
end

function parse(p::ModWithDefault{T, S}, ctx::Context)::ParseResult{S, String} where {T, S}
    result = parse(p.parser, ctx)::ParseResult{S, String}

    if !is_error(result)
        parse_ok = unwrap(result)
        return ParseOk(parse_ok.consumed, parse_ok.next)
    else
        newctx = (@set ctx.state = S(Err(unwrap_error(result).error)))
        return ParseOk(String[], newctx)
    end
end

function complete(p::ModWithDefault{T, S}, st::S)::Result{T, String} where {T, S}
    return is_error(st) ? Ok(p.default) : complete(p.parser, st)
end
