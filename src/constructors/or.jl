const OrState{X} = Tuple{Int,X} # X should be a Tuple of Option{ParseSuccess{SP1}} etc

# a parser that returns the first parsers that matches, in the order provided!
struct ConstrOr{T,S,p,P} <: AbstractParser{T, S, p, P}
    initialState::S
    parsers::P
end

ConstrOr(parsers::Tuple) = let
    # inner_state_t = map(parsers) do p
    #     Option{ParseSuccess{tstate(p)}}
    # end
    inner_state = map(parsers) do p
        none(ParseSuccess{tstate(p)})
    end
    actual_parsers = map(unwrapunion, parsers)
    ConstrOr{
        Union{map(tval, parsers)...},
        OrState{typeof(inner_state)},
        mapreduce(p -> priority(p), max, parsers),
        typeof(parsers)
    }((0, inner_state), parsers)
end


@generated function _generated_or_parse(parsers::PTup, ctx::Context) where {PTup <: Tuple}
    preamble = quote
        error = length(ctx.buffer) < 1 ?
            (0, "No matching option or command.") : (0, "Unexpected option or subcommand: $(ctx.buffer[1])")
    end
    N = length(PTup.parameters)
    unrolled_loop = Expr(:block)
    for i in 1:N
        parser_t = PTup.parameters[i]
        push!(unrolled_loop.args, quote
            parser = parsers[$i]::$parser_t
            innerstate = ctx.state[2][$i]
            childstate = is_error(innerstate) ? parser.initialState : unwrap(innerstate).next.state
            childctx = @set ctx.state = childstate

            result = (@unionsplit parse(parser, childctx))::ParseResult{tstate(parser), String}
            if !is_error(result) && length(unwrap(result).consumed) > 0 # (ignores constants)
                parse_ok = unwrap(result)

                # If we successfully match something, but the current state is telling us that we've already matched
                # something else,
                # and those two things aren't the same thing, then error. 'Or' only matches one parser.
                if ctx.state[1] != 0 && ctx.state[1] != $i
                    already_matched_state_id = ctx.state[1]
                    return ParseErr(length(ctx.buffer) - length(parse_ok.next.buffer),
                        "$(unwrap(ctx.state[2][already_matched_state_id]).consumed[1]) and $(parse_ok.consumed[1]) can't be used together.")
                end

                new_innerstate = set(ctx.state[2], IndexLens($i), some(parse_ok))


                return ParseOk(
                    parse_ok.consumed, Context(
                        parse_ok.next.buffer,
                        ($i, new_innerstate),
                        parse_ok.next.optionsTerminated
                    )
                )
            elseif is_error(result)
                if error[1] < unwrap_error(result).consumed
                    parse_err = unwrap_error(result)
                    error = (parse_err.consumed, parse_err.error)
                end
            end
        end)
    end

    epilogue = :(return ParseErr(error[1], error[2]))

    return quote
        $preamble
        $unrolled_loop
        $epilogue
    end
end

(parse(p::ConstrOr{T, OrState{S}}, ctx::Context{OrState{S}})::ParseResult{OrState{S},String}) where {T, S} =
    _generated_or_parse(p.parsers, ctx)

# function _parse(p::ConstrOr{T, OrState{S}}, ctx::Context{OrState{S}})::ParseResult{OrState{S},String} where {T, S}
#     error = length(ctx.buffer) < 1 ?
#             (0, "No matching option or command.") : (0, "Unexpected option or subcommand: $(ctx.buffer[1])")

#     @info Base.remove_linenums!(_generated_or_parse(p.parsers, ctx))
#     i = 1
#     for parser in p.parsers

#         innerstate = ctx.state[2][i]
#         childstate = is_error(innerstate) ?  parser.initialState : unwrap(innerstate).next.state
#         childctx = @set ctx.state = childstate

#         result = (@unionsplit parse(parser, childctx))::ParseResult{tstate(parser), String}
#         if !is_error(result) && length(unwrap(result).consumed) > 0 # (ignores constants)
#             parse_ok = unwrap(result)

#             # If we successfully match something, but the current state is telling us that we've already matched
#             # something else,
#             # and those two things aren't the same thing, then error. 'Or' only matches one parser.
#             if ctx.state[1] != 0 && ctx.state[1] != i
#                 already_matched_state_id = ctx.state[1]
#                 return ParseErr(length(ctx.buffer) - length(parse_ok.next.buffer),
#                     "$(unwrap(ctx.state[2][already_matched_state_id]).consumed[1]) and $(parse_ok.consumed[1]) can't be used together.")
#             end

#             new_innerstate = set(ctx.state[2], IndexLens(i), some(parse_ok))


#             return ParseOk(
#                 parse_ok.consumed, Context(
#                     parse_ok.next.buffer,
#                     (i, new_innerstate),
#                     parse_ok.next.optionsTerminated
#                 )
#             )
#         elseif is_error(result)
#             if error[1] < unwrap_error(result).consumed
#                 parse_err = unwrap_error(result)
#                 error = (parse_err.consumed, parse_err.error)
#             end
#         end
#         i += 1
#     end

#     return ParseErr(error[1], error[2])
# end

function complete(p::ConstrOr{T}, orstate::OrState{S})::Result{T,String} where {T,S}
    orstate[1] == 0 && return Err("No matching option or command.")
    ith, allmaybestates = orstate

    result = @unionsplit complete(p.parsers[ith], unwrap(allmaybestates[ith]).next.state)

    if !is_error(result)
        return Ok(unwrap(result))
    else
        return Err(unwrap_error(result))
    end

end