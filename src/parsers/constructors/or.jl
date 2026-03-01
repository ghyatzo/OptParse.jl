const _InnerState = Tuple{Vararg{Option{<:ParseSuccess}}} # just for explicitness

const OrState{I, X} = Tuple{I, X} # X <: _InnerState and I == Val{int position}

# a parser that returns the first parsers that matches, in the order provided!
struct ConstrOr{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    parsers::P
end

# todo! define a parametric wrapped union that stores all possible states.
@wrapped struct OrState{U}
    union::U
end
# the union is made out of possible states! we can then forgo the Val part most likely!

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
        error = ctx_haslessthan(1, ctx) ?
            ParseFailure(0, "Expected token, got end of input.") : ParseFailure(0, "Unexpected option or subcommand: $(ctx.buffer[1])")
    end
    N = fieldcount(PTup)
    unrolled_loop = Expr(:block)

    valunion = Union{map(typeof ∘ Val, Tuple(collect(0:N)))...}
    for i in 1:N
        #=Iterate through all child parsers in order of priority.=#
        child_parser_t = fieldtype(PTup, i)
        child_parser_tstate = tstate(child_parser_t)
        push!(
            unrolled_loop.args, quote
                parser = parsers[$i]::$child_parser_t

                innerstate = ℒ_state(ctx)[2][$i]
                childstate = is_error(innerstate) ? parser.initialState : ℒ_nextstate(unwrap(innerstate))
                childctx = widen_restate($child_parser_tstate, ctx, childstate)

                result = (@unionsplit parse(parser, childctx))::ParseResult{tstate(parser), String}
                if !is_error(result) && length(unwrap(result).consumed) > 0 # (ignores constants)
                    parse_ok = unwrap(result)

                    #=If we successfully match something, but the current state is telling us that we've already matched
                    # something else,
                    # and those two things aren't the same thing, then error. 'Or' only matches one parser.=#
                    if $j != 0 && $j != $i
                        jstate = ℒ_state(ctx)[2][$j]
                        return parseerr(ctx,
                            "$(unwrap(jstate).consumed[1]) and $(parse_ok.consumed[1]) can't be used together.";
                            consumed=ctx_length(ctx) - ctx_length(ℒ_nextctx(parse_ok))
                        )
                    end


                    new_innerstate = set(ℒ_state(ctx)[2], IndexLens($i), some(parse_ok))
                    nextctx = widen_restate(OrState{$valunion, $X}, ℒ_nextctx(parse_ok), (Val($i), new_innerstate))
                    return parseok(nextctx, ℒ_consumed(parse_ok))

                elseif is_error(result)
                    if error.consumed < unwrap_error(result).consumed
                        error = parseerr(unwrap_error(result))
                    end
                end
            end
        )
    end

    epilogue = :(return parseerr(error))

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

    convert(ParseResult{OrState{valunion, state_t}, String}, _generated_or_parse(p.parsers, ctx, ℒ_state(ctx)[1]))
end

# function complete(p::ConstrOr{Or{U}}, orstate::OrState{Val{i}, S})::Result{Or{U}, String} where {i, U, S}
#     i == 0 && return Err("No matching option or command.")
#     _, allmaybestates = orstate

#     result = @unionsplit complete(p.parsers[i], ℒ_nextstate(unwrap(allmaybestates[i])))

#     return Ok(@? Or{U}(result))
@generated function complete(
        p::ConstrOr{U, OrState{I, S}, _p, P},
        orstate::OrState{I, S}
    )::Result{U, String} where {U, I, S, _p, P}

    vals = Base.uniontypes(I)
    ex = quote
        idx, allmaybestates = orstate
    end

    for V in vals
        i = V.parameters[1]

        if i == 0
            push!(ex.args, quote
                if idx isa Val{0}
                    return Result{$U, String}(Err("No matching option or command."))
                end
            end)
            continue
        end

        parser_t = fieldtype(P, i)
        val_t = tval(parser_t)
        push!(ex.args, quote
            if idx isa Val{$i}
                parser = p.parsers[$i]::$parser_t
                maybestate = allmaybestates[$i]
                result = Result{$val_t, String}(complete(
                    unwrapunion(parser),
                    ℒ_nextstate(unwrap(maybestate))
                ))

                if is_error(result)
                    return Result{$U, String}(Err(unwrap_error(result)))
                end

                return Result{$U, String}(Ok(unwrap(result)))
            end
        end)
    end

    push!(ex.args, :(return Result{$U, String}(Err("No matching option or command."))))
    return ex
end
