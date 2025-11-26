const OrState{I, X} = Tuple{I, X} # X should be a Tuple of Option{ParseSuccess{SP1}} and I a Val{int position}

# a parser that returns the first parsers that matches, in the order provided!
struct ConstrOr{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    parsers::P
end

ConstrOr(parsers::PTup) where {PTup <: Tuple} = let

    inner_state = map(parsers) do p
        none(ParseSuccess{tstate(p)})
    end

    possible_vals = ntuple(fieldcount(PTup) + 1) do i
        Val{i - 1}
    end
    ConstrOr{
        Union{map(tval, parsers)...},
        OrState{Union{possible_vals...}, typeof(inner_state)},
        mapreduce(p -> priority(p), max, parsers),
        typeof(parsers),
    }((Val(0), inner_state), parsers)
end

@generated function _generated_or_parse(parsers::PTup, ctx::Context{OrState{I, X}}, ::Val{j}) where {PTup <: Tuple, I, X <: Tuple, j}
    preamble = quote
        error = length(ctx.buffer) < 1 ?
            (0, "No matching option or command.") : (0, "Unexpected option or subcommand: $(ctx.buffer[1])")
    end
    N = fieldcount(PTup)
    unrolled_loop = Expr(:block)

    valunion = Union{map(typeof ∘ Val, Tuple(collect(0:N)))...}
    for i in 1:N
        parser_t = fieldtype(PTup, i)
        parser_tstate = tstate(parser_t)
        push!(
            unrolled_loop.args, quote
                parser = parsers[$i]::$parser_t
                innerstate = ctx.state[2][$i]
                childstate = is_error(innerstate) ? parser.initialState : unwrap(innerstate).next.state
                childctx = Context{$parser_tstate}(ctx.buffer, childstate, ctx.optionsTerminated)

                result = (@unionsplit parse(parser, childctx))::ParseResult{tstate(parser), String}
                if !is_error(result) && length(unwrap(result).consumed) > 0 # (ignores constants)
                    parse_ok = unwrap(result)

                    # If we successfully match something, but the current state is telling us that we've already matched
                    # something else,
                    # and those two things aren't the same thing, then error. 'Or' only matches one parser.
                    if $j != 0 && $j != $i
                        return ParseErr(
                            length(ctx.buffer) - length(parse_ok.next.buffer),
                            "$(unwrap(ctx.state[2][$j]).consumed[1]) and $(parse_ok.consumed[1]) can't be used together."
                        )
                    end

                    new_innerstate = set(ctx.state[2], IndexLens($i), some(parse_ok))

                    return ParseOk(
                        parse_ok.consumed, Context{OrState{$valunion, $X}}(
                            parse_ok.next.buffer,
                            (Val($i), new_innerstate),
                            parse_ok.next.optionsTerminated
                        )
                    )
                elseif is_error(result)
                    if error[1] < unwrap_error(result).consumed
                        parse_err = unwrap_error(result)
                        error = (parse_err.consumed, parse_err.error)
                    end
                end
            end
        )
    end

    epilogue = :(return ParseErr(error[1], error[2]))

    return quote
        $preamble
        $unrolled_loop
        $epilogue
    end
end

parse(p::ConstrOr{T, OrState{I, S}}, ctx::Context{OrState{I, S}}) where {T, I, S <: Tuple} = let
    valunion = Union{ntuple(i -> Val{i - 1}, fieldcount(S) + 1)...}
    state_t = typeof(
        map(p.parsers) do p
            none(ParseSuccess{tstate(p)})
        end
    )

    convert(ParseResult{OrState{valunion, state_t}, String}, _generated_or_parse(p.parsers, ctx, ctx.state[1]))
end

function complete(p::ConstrOr{T}, orstate::OrState{Val{i}, S})::Result{T, String} where {i, T, S}
    i == 0 && return Err("No matching option or command.")
    _, allmaybestates = orstate

    result = @unionsplit complete(p.parsers[i], unwrap(allmaybestates[i]).next.state)

    if !is_error(result)
        return Ok(unwrap(result))
    else
        return Err(unwrap_error(result))
    end

end
