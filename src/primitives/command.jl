const CommandState{X} = Option{Option{X}}


struct ArgCommand{T, S, _p, P} <: AbstractParser{T, S, _p, P}
    initialState::S
    parser::P
    #
    name::String
    brief::String
    description::String
    footer::String

    ArgCommand(name, parser::P; brief = "", description = "", footer = "") where {P} =
        new{tval(P), CommandState{tstate(P)}, 15, P}(none(Option{tstate(P)}), parser, name, brief, description, footer)
end

# parse(p::ArgCommand, ctx)::ParseResult{String,String} = ParseErr(0, "Invalid command state. (YOU REACHED AN UNREACHABLE).")


function parse(p::ArgCommand{T, CommandState{PState}}, ctx::Context{CommandState{PState}})::ParseResult{CommandState{PState}, String} where {T, PState}
    if is_error(ctx.state)
        # command not yet matched
        # check if it starts with our command name
        if length(ctx.buffer) < 1 || ctx.buffer[1] != p.name
            actual = length(ctx.buffer) > 0 ? ctx.buffer[1] : nothing

            if actual === nothing
                return ParseErr(0, "Expected command `$(p.name)`, but got end of input.")
            end

            return ParseErr(0, "Expected command `$(p.name)`, but got `$actual`.")
        end

        # command matched, consume it and move to the matched state
        return ParseOk(
            ctx.buffer[1:1], Context{CommandState{PState}}(
                ctx.buffer[2:end],
                some(none(PState)),
                ctx.optionsTerminated
            )
        )
    else
        maybestate = base(unwrap(ctx.state))
        childstate = isnothing(maybestate) ? p.parser.initialState : @something maybestate
        childctx = Context{tstate(p.parser)}(ctx.buffer, childstate, ctx.optionsTerminated)

        result = parse(unwrapunion(p.parser), childctx)::ParseResult{PState, String}

        if !is_error(result)
            parse_ok = unwrap(result)

            nextctx = parse_ok.next
            return ParseOk(
                parse_ok.consumed,
                Context{CommandState{PState}}(nextctx.buffer, some(some(nextctx.state)), nextctx.optionsTerminated)
            )
        else
            parse_err = unwrap_error(result)
            return ParseErr(parse_err.consumed, parse_err.error)
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
        return Err("Command $(p.name) was not matched")
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
