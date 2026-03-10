# const _InnerState = Tuple{Vararg{Option{<:ParseSuccess}}} # just for explicitness

# const OrState{I, X} = Tuple{I, X} # X <: _InnerState and I == Val{int position}

# todo! define a parametric wrapped union that stores all possible states.
@wrapped struct InnerOrState{U}
    union::U
end

const OrState{U} = Option{InnerOrState{U}}
# the union is made out of possible states! we can then forgo the Val part most likely!

# a parser that returns the first parsers that matches, in the order provided!
struct ConstrOr{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    parsers::P
end

ConstrOr(parsers::PTup) where {PTup <: Tuple} = let

    inner_state_types = map(parsers) do p
        ParseSuccess{tstate(p)}
    end
    innerstate_U = Union{inner_state_types...}

    ConstrOr{
        Union{map(tval, parsers)...},
        OrState{innerstate_U},
        mapreduce(p -> priority(p), max, parsers),
        typeof(parsers),
    }(none(InnerOrState{innerstate_U}), parsers)
end

@generated function _generated_or_parse(parsers::PTup, ctx::Context{OrState{U}}, current_res::ResType) where {PTup <: Tuple, U, ResType}
    preamble = quote
        error = ctx_haslessthan(1, ctx) ?
            ParseFailure(0, "Expected token, got end of input.") : ParseFailure(0, "Unexpected option or subcommand: $(ctx.buffer[1])")
    end
    N = fieldcount(PTup)
    unrolled_loop = Expr(:block)

    for i in 1:N
        child_parser_t = fieldtype(PTup, i)
        child_parser_tstate = tstate(child_parser_t)

        push!(unrolled_loop.args, quote
            parser = parsers[$i]::$child_parser_t
            innerstate = ℒ_state(ctx)
            if is_error(innerstate)
                childstate = parser.initialState
            else
                selected_state = unwrapunion(unwrap(innerstate))
                childstate = selected_state isa ParseSuccess{$child_parser_tstate} ?
                    ℒ_nextstate(selected_state) : parser.initialState
            end
            childctx = ctx_with_state(ctx, childstate)

            result = (@unionsplit parse(parser, childctx))::ParseResult{tstate(parser), String}
            if !is_error(result) && length(unwrap(result).consumed) > 0
                parse_ok = unwrap(result)

                #=If we successfully match something, but the current state is telling us that we've already matched
                # something else,
                # and those two things aren't the same thing, then error. 'Or' only matches one parser.=#

                if !($ResType != Nothing) && !(ParseSuccess{$child_parser_tstate} <: $ResType)
                    return parseerr(ctx,
                        "$(unwrap(current_res).consumed[1]) and $(parse_ok.consumed[1]) can't be used together.";
                        consumed=ctx_length(ctx) - ctx_length(ℒ_nextctx(parse_ok))
                    )
                end

                new_innerstate = some(InnerOrState(parse_ok))
                newctx = ctx_restate(ℒ_nextctx(parse_ok), new_innerstate)
                return parseok(newctx, ℒ_consumed(parse_ok))
            elseif is_error(result)
                if ℒ_consumed(error) < ℒ_consumed(unwrap_error(result))
                    error = unwrap_error(result)
                end
            end
        end)

    end

    epilogue = :(return parseerr(error))

    return quote
        $preamble
        $unrolled_loop
        $epilogue
    end
end

parse(p::ConstrOr{T, OrState{U}}, ctx::Context{OrState{U}}) where {T,U} = let

    inner_state_types = map(p.parsers) do par
        ParseSuccess{tstate(par)}
    end
    innerstate_U = Union{inner_state_types...}

    currstate = is_error(ℒ_state(ctx)) ? Nothing : unwrap(ℒ_state(ctx))

    convert(ParseResult{OrState{innerstate_U}, String}, _generated_or_parse(p.parsers, ctx, currstate))
end

function complete(p::ConstrOr{T}, orstate::OrState{U})::Result{T, String} where {T, U}
    is_error(orstate) && return Err("No matching option or command.")

    state = ℒ_nextstate(unwrapunion(unwrap(orstate)))

    result = _gencomplete(p.parsers, state)

    # result = @unionsplit complete(p.parsers[i], ℒ_nextstate(unwrap(allmaybestates[i])))

    return Ok(@? result)
end

@generated function _gencomplete(
        parsers::PTup,
        orstate::SelectedState
    )::Result{T, String} where {PTup<:Tuple, SelectedState}

    N = fieldcount(PTup)
    for i in 1:N
        ptype = fieldtype(PTup, i)
        pstatetype = tstate(ptype)

        if pstatetype == SelectedState
            return :(@unionsplit complete(parsers[$i], orstate))
        end
    end

    return :(Err("Unreachable"))
end

# @generated function complete(
#         p::ConstrOr{U, OrState{I, S}, _p, P},
#         orstate::OrState{I, S}
#     )::Result{U, String} where {U, I, S, _p, P}

#     vals = Base.uniontypes(I)
#     ex = quote
#         idx, allmaybestates = orstate
#     end

#     for V in vals
#         i = V.parameters[1]

#         if i == 0
#             push!(ex.args, quote
#                 if idx isa Val{0}
#                     return Result{$U, String}(Err("No matching option or command."))
#                 end
#             end)
#             continue
#         end

#         parser_t = fieldtype(P, i)
#         val_t = tval(parser_t)
#         push!(ex.args, quote
#             if idx isa Val{$i}
#                 parser = p.parsers[$i]::$parser_t
#                 maybestate = allmaybestates[$i]
#                 result = Result{$val_t, String}(complete(
#                     unwrapunion(parser),
#                     ℒ_nextstate(unwrap(maybestate))
#                 ))

#                 if is_error(result)
#                     return Result{$U, String}(Err(unwrap_error(result)))
#                 end

#                 return Result{$U, String}(Ok(unwrap(result)))
#             end
#         end)
#     end

#     push!(ex.args, :(return Result{$U, String}(Err("No matching option or command."))))
#     return ex
# end
