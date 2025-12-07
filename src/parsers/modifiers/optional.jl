# DONE: make the optional parser a special case of the withDefault parser that returns nothing.
# We keep this around just in case we need to special case the help printing and usage.

const OptionalState{X} = Option{X}

struct ModOptional{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    parser::P

    ModOptional(parser::P) where {P} =
        new{Union{Nothing, tval(P)}, OptionalState{tstate(P)}, priority(P), P}(none(tstate(P)), parser)
end


function parse(p::ModOptional{T, OptionalState{S}}, ctx::Context{OptionalState{S}})::ParseResult{OptionalState{S}, String} where {T, S}

    childstate = is_error(ctx.state) ? p.parser.initialState : unwrap(ctx.state)
    childctx = Context{S}(ctx.buffer, childstate, ctx.optionsTerminated)
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

function complete(p::ModOptional{T, OptionalState{S}, _p, P}, maybestate::OptionalState{S})::Result{T, String} where {T, S, _p, P}
    #=If we receive a none, the parser failed to parse. Then return the nothing.
    Otherwise, unwrap the state, give it to the child parser for completion and return the result.=#
    state = @unwrap_or maybestate (return Ok(nothing))

    result = complete(unwrapunion(p.parser), state)::Result{tval(P), String}

    # unwrap or return the error
    return Ok(@? result)
end


# comments with some insights:
#=
There is currently an issue. We need a mechanism to allow bypassing this check
To allow for potential "fixable" errors (think optional) to pass through to the
complete function. At first we simply updated the state, which works for single state
parsers, but fails completely for multistate ones
=#
#=
This is correct, no need to bypass anything. The error was that the optional parser
was returning its child parse error as an error, while an optional parser
should alway return a success with an error state, which can be picked up in the complete function
but doesn't count as a proper Parseerror
=#
