

@sum_type CommandState{X} :hidden begin
    NotMatched
    MatchedEmpty
    Matched{X}(x::X)
end

@enum CommandErrCode::UInt8 begin
    COMMAND_EndOfInput
    COMMAND_WrongName
    COMMAND_NotMatched
end

struct ArgCommandError <: AbstractParseError
    code::CommandErrCode
    token::String
    detail::String
end

function render_error(io::IO, err::ArgCommandError)
    return if err.code == COMMAND_EndOfInput
        print(io, "Expected command $(err.detail), got end of input")
    elseif err.code == COMMAND_WrongName
        print(io, "Expected command $(err.detail), got $(err.token)")
    elseif err.code == COMMAND_NotMatched
        print(io, "Command $(err.detail) was not matched")
    else
        print(io, "unreachable")
    end
end


struct ArgCommand{T, E, S, P, R} <: AbstractParser{T, E, S, P, R}
    initialState::S
    parser::P
    #
    names::Vector{String}

    ArgCommand(names::Tuple{Vararg{String}}, parser::P) where {P <: AbstractParser} =
        new{
            val_t(P),
            Union{ArgCommandError, err_t(P)},
            CommandState{state_t(P)},
            P,
            15
        }(
            CommandState{state_t(P)}'.NotMatched,
            parser,
            [names...],
        )
end

usage(p::ArgCommand) = UsageCommand(p.names, usage(p.parser)::UsageNode)

helpentries(p::ArgCommand, rt::OverlayContext) = [HelpEntry(usage(p), helpinfo(rt))]

@autospecialize p ctx function focused_helpdoc(
        p::ArgCommand{<:Any, <:Any, S},
        ctx::Context{S},
        prefix::Vector{String},
        rt::OverlayContext
    )::HelpDoc where {S <: CommandState}

    child_state = @cases state(ctx) begin

        NotMatched => return HelpDoc(
            prefix,
            usage(p),
            helpinfo(rt),
            helpentries(p.parser, descend_child(rt))::Vector{HelpEntry}
        )

        MatchedEmpty => p.parser.initialState)
        Matched(st) => st
    end

    child_ctx = widen_restate(state_t(p.parser), ctx, child_state)
    child_prefix = _usage_push_prefix(prefix, first(p.names))

    return focused_helpdoc(p.parser, child_ctx, child_prefix, descend_child(rt))::HelpDoc
end

@autospecialize p ctx function parse(p::ArgCommand{<:Any, E, S}, ctx::Context{S}) where {E, S <: CommandState}

    IS = state_t(typeof(p.parser))

    (; NotMatched, MatchedEmpty, Matched) = CommandState{IS}'

    childctx = @cases state(ctx) begin

        NotMatched => begin
            if hasnone(ctx) || peek(ctx) ∉ p.names
                actual = hasnone(ctx) ? nothing : peek(ctx)
                if actual === nothing
                    return InnerParseResult{S, E}(innerErr(ArgCommandError(COMMAND_EndOfInput, "", p.names[1])))
                end

                return InnerParseResult{S, E}(innerErr(ArgCommandError(COMMAND_WrongName, actual, p.names[1])))
            end

            nextctx = with_state(ctx, MatchedEmpty)
            return InnerParseResult{S, E}(innerOk(nextctx, 1))
        end

        MatchedEmpty => widen_restate(IS, ctx, p.parser.initialState)
        Matched(st) => widen_restate(IS, ctx, st)

    end

    result = parse(p.parser, childctx)
    is_error(result) && return InnerParseResult{S, E}(innerErr(E, result))

    parse_ok = unwrap(result)
    newctx = widen_restate(
        S,
        res_nextctx(parse_ok),
        Matched(res_nextstate(parse_ok))
    )
    return InnerParseResult{S, E}(innerOk(newctx, res_consumed(parse_ok)))
end

@autospecialize p function complete(p::ArgCommand{T, E, S}, cmdst::S) where {T, E, S <: CommandState}

    result = @cases cmdst begin
        NotMatched => return ParseResult{T, E}(typedErr(E, ArgCommandError(COMMAND_NotMatched, "", p.names[1])))

        MatchedEmpty => complete(p.parser, p.parser.initialState)

        Matched(st) => complete(p.parser, st)
    end

    if is_error(result)
        return ParseResult{T, E}(typedErr(E, unwrap_error(result)))
    else
        return ParseResult{T, E}(typedOk(T, unwrap(result)))
    end
end
