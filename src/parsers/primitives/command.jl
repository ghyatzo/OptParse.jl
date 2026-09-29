const CommandState{X} = Option{Option{X}}


# @sum_type struct CommandState{X}
#     CommandNotMatched{X}
#     CommandMatchedEmpty{X}
#     CommandMatched{X}(x::X)
# end


# struct CommandNotMatched{X} end
# struct CommandMatchedEmpty{X} end
# struct CommandMatched{X}; x::X end

# @wrapped struct CommandState{X}
#     union::Union{
#         CommandNotMatched{X},
#         CommandMatchedEmpty{X},
#         CommandMatched{X}
#     }
# end

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
            none(Option{state_t(P)}),
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
    if is_error(state(ctx))
        # the command failed to parse. This is the root node.
        return HelpDoc(
            prefix,
            usage(p),
            helpinfo(rt),
            helpentries(p.parser, descend_child(rt))::Vector{HelpEntry}
        )
    end

    maybestate = unwrap(state(ctx))
    child_state = is_error(maybestate) ? p.parser.initialState : unwrap(maybestate)
    child_ctx = widen_restate(state_t(p.parser), ctx, child_state)
    child_prefix = _usage_push_prefix(prefix, first(p.names))

    return focused_helpdoc(p.parser, child_ctx, child_prefix, descend_child(rt))::HelpDoc
end

@autospecialize p ctx function parse(p::ArgCommand{T, E, S}, ctx::Context{S}) where {T, E, S <: CommandState}
    IS = state_t(typeof(p.parser))

    if is_error(state(ctx))
        # command not yet matched
        # check if it starts with our command name
        if hasnone(ctx) || peek(ctx) ∉ p.names
            actual = hasnone(ctx) ? nothing : peek(ctx)

            if actual === nothing
                return InnerParseResult{S, E}(innerErr(ArgCommandError(COMMAND_EndOfInput, "", p.names[1])))
            end

            return InnerParseResult{S, E}(innerErr(ArgCommandError(COMMAND_WrongName, actual, p.names[1])))
        end

        # command matched, consume it and move to the matched state
        nextctx = with_state(ctx, some(none(IS)))
        return InnerParseResult{S, E}(innerOk(nextctx, 1))

    else
        maybestate = base(unwrap(state(ctx)))
        childstate = isnothing(maybestate) ? p.parser.initialState : @something maybestate
        childctx = widen_restate(IS, ctx, childstate)

        result = parse(p.parser, childctx)

        if !is_error(result)
            parse_ok = unwrap(result)

            newctx = widen_restate(
                S,
                res_nextctx(parse_ok),
                some(some(res_nextstate(parse_ok)))
            )
            return InnerParseResult{S, E}(innerOk(newctx, res_consumed(parse_ok)))

        else
            return InnerParseResult{S, E}(innerErr(E, result))
        end
    end
end

@autospecialize p function complete(p::ArgCommand{T, E, S}, maybemaybestate::S) where {T, E, S <: CommandState}

    if is_error(maybemaybestate)
        # command never matched
        return ParseResult{T, E}(typedErr(E, ArgCommandError(COMMAND_NotMatched, "", p.names[1])))
    else
        maybestate = unwrap(maybemaybestate)
        result = if is_error(maybestate)
            # command matched but the inner parser never started: pass in the initialState
            complete(p.parser, p.parser.initialState)
        else
            complete(p.parser, unwrap(maybestate))
        end

        if is_error(result)
            return ParseResult{T, E}(typedErr(E, unwrap_error(result)))
        else
            return ParseResult{T, E}(typedOk(T, unwrap(result)))
        end
    end
end
