@wrapped struct InnerOrState{U}
    union::U
end

struct OrBranchState{I, S}
    success::ParseSuccess{S}
end

const OrState{U} = Option{InnerOrState{U}}

Base.@assume_effects :foldable function _or_inner_branch_union(::Type{PTup}) where {PTup <: Tuple}
    branch_types = ntuple(fieldcount(PTup)) do i
        ptype = fieldtype(PTup, i)
        OrBranchState{i, tstate(ptype)}
    end
    return Union{branch_types...}
end

# a parser that returns the first parsers that matches, in the order provided!
struct ConstrOr{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    parsers::P
end

ConstrOr(parsers::PTup) where {PTup <: Tuple} = let

    innerstate_U = _or_inner_branch_union(PTup)

    ConstrOr{
        Union{map(tval, parsers)...},
        OrState{innerstate_U},
        mapreduce(p -> priority(p), max, parsers),
        typeof(parsers),
    }(none(InnerOrState{innerstate_U}), parsers)
end

@generated function _generated_or_parse(parsers::PTup, ctx::Context{OrState{U}}) where {PTup <: Tuple, U}
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
            has_selection = !is_error(innerstate)


            if is_error(innerstate)
                childstate = parser.initialState
            else
                selected_state = unwrapunion(unwrap(innerstate))
                childstate = selected_state isa OrBranchState{$i, $child_parser_tstate} ?
                    ℒ_nextstate(selected_state.success) : parser.initialState
            end
            childctx = ctx_with_state(ctx, childstate)

            result = (@unionsplit parse(parser, childctx))::ParseResult{tstate(parser), String}
            if !is_error(result) && length(unwrap(result).consumed) > 0
                parse_ok = unwrap(result)

                #=If we successfully match something, but the current state is telling us that we've already matched
                # something else,
                # and those two things aren't the same thing, then error. 'Or' only matches one parser.=#

                if has_selection && !(selected_state isa OrBranchState{$i, $child_parser_tstate})
                    return parseerr(ctx,
                        "$(selected_state.success.consumed[1]) and $(parse_ok.consumed[1]) can't be used together.";
                        consumed=ctx_length(ctx) - ctx_length(ℒ_nextctx(parse_ok))
                    )
                end

                new_innerstate = some(InnerOrState{$U}(OrBranchState{$i, $child_parser_tstate}(parse_ok)))
                newctx = widen_restate(OrState{$U}, ℒ_nextctx(parse_ok), new_innerstate)
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

    innerstate_U = _or_inner_branch_union(typeof(p.parsers))

    convert(ParseResult{OrState{innerstate_U}, String}, _generated_or_parse(p.parsers, ctx))
end

function complete(p::ConstrOr{T}, orstate::OrState{U})::Result{T, String} where {T, U}
    is_error(orstate) &&
        return typedErr(T, "No matching option or command.")

    selected = unwrapunion(unwrap(orstate))::U
    return _gencomplete(p, selected)
end

@generated function _gencomplete(
        p::ConstrOr{T, OrState{U}, pprio, PTup},
        selected::U,
    )::Result{T, String} where {T, U, pprio, PTup <: Tuple}
    ex = Expr(:block)

    for branch_t in Base.uniontypes(U)
        branch_t <: OrBranchState || continue

        i = branch_t.parameters[1]
        ptype = fieldtype(PTup, i)
        out_t = tval(ptype)

        push!(ex.args, quote
            if selected isa $branch_t
                child_result = complete(p.parsers[$i], ℒ_nextstate(selected.success))::Result{$out_t, String}
                if is_error(child_result)
                    return typedErr(T, unwrap_error(child_result))
                end
                return typedOk(T, unwrap(child_result)::T)
            end
        end)
    end

    push!(ex.args, :(return typedErr(T, "Unreachable")))
    return ex
end
