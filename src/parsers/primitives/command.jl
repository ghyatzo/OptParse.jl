const CommandState{X} = Option{Option{X}}


struct ArgCommand{T, S, _p, P} <: AbstractParser{T, S, _p, P}
    initialState::S
    parser::P
    #
    names::Vector{String}
    brief::String
    help::String
    footer::String

    ArgCommand(names::Tuple{Vararg{String}}, parser::P; brief = "", help = "", footer = "") where {P} =
        new{tval(P), CommandState{tstate(P)}, 15, P}(none(Option{tstate(P)}), parser, [names...], brief, help, footer)
end


function parse(p::ArgCommand{T, CommandState{PState}}, ctx::Context{CommandState{PState}})::ParseResult{CommandState{PState}, String} where {T, PState}
    if is_error(ℒ_state(ctx))
        # command not yet matched
        # check if it starts with our command name
        if ctx_hasnone(ctx) || ctx_peek(ctx) ∉ p.names
            actual = ctx_hasnone(ctx) ? nothing : ctx_peek(ctx)

            if actual === nothing
                return ParseErr("Expected command `$(p.names[1])`, but got end of input.", ctx)
            end

            return ParseErr("Expected command `$(p.names[1])`, but got `$actual`.", ctx)
        end

        # command matched, consume it and move to the matched state
        nextctx = ctx_with_state(consume(ctx, 1), some(none(PState)))
        return ParseOk(ctx, 1; nextctx)

    else
        maybestate = base(unwrap(ℒ_state(ctx)))
        childstate = isnothing(maybestate) ? p.parser.initialState : @something maybestate
        childctx = widen_restate(tstate(p.parser), ctx, childstate)

        result = parse(unwrapunion(p.parser), childctx)::ParseResult{PState, String}

        if !is_error(result)
            parse_ok = unwrap(result)

            newctx = widen_restate(
                CommandState{PState},
                ℒ_nextctx(parse_ok),
                some(some(ℒ_nextstate(parse_ok)))
            )
            return ok_restate(parse_ok, newctx)

        else
            return err_rethrow(unwrap_error(result))
        end
    end
end

# function parse(p::ArgCommand{T, CommandState{PState}}, ctx::Context{Option{PState}})::ParseResult{CommandState{PState}, String} where {T, PState}
#     maybestate = base(ctx.state)
#     childstate = isnothing(maybestate) ? p.parser.initialState : @something maybestate
#     childctx = @set ctx.state = childstate

#     result = parse(unwrapunion(p.parser), childctx)::ParseResult{PState, String}

#     if !is_error(result)
#         parse_ok = unwrap(result)

#         nextctx = parse_ok.next
#         return ParseOk(
#             parse_ok.consumed,
#             Context{CommandState{PState}}(nextctx.buffer, some(nextctx.state), nextctx.optionsTerminated)
#         )
#     else
#         parse_err = unwrap_error(result)
#         return ParseErr(parse_err.consumed, parse_err.error)
#     end
# end


function complete(p::ArgCommand{T, CommandState{PState}}, maybemaybestate::CommandState{PState})::Result{T, String} where {T, PState}

    if is_error(maybemaybestate)
        # command never matched
        return Err("Command $(p.names[1]) was not matched")
    else
        maybestate = unwrap(maybemaybestate)
        if is_error(maybestate)
            # command matched but the inner parser never started: pass in the initialState
            return complete(unwrapunion(p.parser), p.parser.initialState)
        else
            return complete(unwrapunion(p.parser), unwrap(maybestate))
        end
    end
end
