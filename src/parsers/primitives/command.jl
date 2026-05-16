const CommandState{X} = Option{Option{X}}

_inner_state(::Type{CommandState{X}}) where {X} = X

@enum CommandErrCode::UInt8 begin
    COMMAND_EndOfInput
    COMMAND_WrongName
    COMMAND_NotMatched
end

argcommand_error(code::CommandErrCode; token = "", detail = "", subject = "") =
    mkerror(
    ERR_ArgCommand, UInt8(code);
    token,
    detail,
    subject
)

function argcommand_render_error(io::IO, code::CommandErrCode, err::ParseError)
    return if code == COMMAND_EndOfInput
        print(io, "Expected command $(err.detail), got end of input")
    elseif code == COMMAND_WrongName
        print(io, "Expected command $(err.detail), got $(err.token)")
    elseif code == COMMAND_NotMatched
        print(io, "Command $(err.detail) was not matched")
    else
        print(io, "unreachable")
    end
end


struct ArgCommand{T, S, _p, P} <: AbstractParser{T, S, _p, P}
    initialState::S
    parser::P
    #
    names::Vector{String}

    ArgCommand(names::Tuple{Vararg{String}}, parser::P) where {P <: AbstractParser} =
        new{tval(P), CommandState{tstate(P)}, 15, P}(
        none(Option{tstate(P)}),
        parser,
        [names...],
    )
end

usage(p::ArgCommand) = UsageCommand(p.names, usage(p.parser)::UsageNode)

helpentries(p::ArgCommand, rt::OverlayContext) = [HelpEntry(usage(p), helpinfo(rt))]

@autospecialize p ctx function focused_helpdoc(
        p::ArgCommand{T, S},
        ctx::Context{S},
        prefix::Vector{String},
        rt::OverlayContext
    )::HelpDoc where {T, S <: CommandState}
    if is_error(ctx_state(ctx))
        # the command failed to parse. This is the root node.
        return HelpDoc(
            prefix,
            usage(p),
            helpinfo(rt),
            helpentries(p.parser, descend_child(rt))::Vector{HelpEntry}
        )
    end

    maybestate = unwrap(ctx_state(ctx))
    child_state = is_error(maybestate) ? p.parser.initialState : unwrap(maybestate)
    child_ctx = widen_restate(tstate(p.parser), ctx, child_state)
    child_prefix = _usage_push_prefix(prefix, first(p.names))

    return focused_helpdoc(p.parser, child_ctx, child_prefix, descend_child(rt))::HelpDoc
end

@autospecialize p ctx function parse(p::ArgCommand{T, S}, ctx::Context{S})::InnerParseResult{S} where {T, S <: CommandState}
    if is_error(ctx_state(ctx))
        # command not yet matched
        # check if it starts with our command name
        if ctx_hasnone(ctx) || ctx_peek(ctx) ∉ p.names
            actual = ctx_hasnone(ctx) ? nothing : ctx_peek(ctx)

            if actual === nothing
                return innerErr(ctx, argcommand_error(COMMAND_EndOfInput; detail = p.names[1]))
            end

            return innerErr(ctx, argcommand_error(COMMAND_WrongName; token = actual, detail = p.names[1]))
        end

        # command matched, consume it and move to the matched state
        nextctx = ctx_with_state(consume(ctx, 1), some(none(_inner_state(S))))
        return innerOk(ctx, 1; nextctx)

    else
        maybestate = base(unwrap(ctx_state(ctx)))
        childstate = isnothing(maybestate) ? p.parser.initialState : @something maybestate
        childctx = widen_restate(tstate(p.parser), ctx, childstate)

        result = parse(p.parser, childctx)::InnerParseResult{_inner_state(S)}

        if !is_error(result)
            parse_ok = unwrap(result)

            newctx = widen_restate(
                S,
                res_nextctx(parse_ok),
                some(some(ℒ_nextstate(parse_ok)))
            )
            return innerOk(newctx, res_consumed(parse_ok))

        else
            return innerErr(ctx, result)
        end
    end
end

@autospecialize p function complete(p::ArgCommand{T, S}, maybemaybestate::S)::ParseResult{T} where {T, S <: CommandState}

    if is_error(maybemaybestate)
        # command never matched
        return typedErr(T, argcommand_error(COMMAND_NotMatched; detail = p.names[1]))
    else
        maybestate = unwrap(maybemaybestate)
        result = if is_error(maybestate)
            # command matched but the inner parser never started: pass in the initialState
            complete(p.parser, p.parser.initialState)
        else
            complete(p.parser, unwrap(maybestate))
        end
        return !is_error(result) ? result : typedErr(
                T,
                error_with_subject(
                    result,
                    p.names[1]
                )
            )
    end
end
