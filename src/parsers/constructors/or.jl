@wrapped struct InnerOrState{U}
    union::U
end

struct OrBranchState{I, S}
    success::InnerParseSuccess{S}
end

const OrState{U} = Option{InnerOrState{U}}

@enum OrErrCode::UInt8 begin
    OR_EndOfInput
    OR_UnexpectedToken
    OR_Conflict
    OR_NoMatch
    OR_Unreachable
end

constror_error(code::OrErrCode; token = "", detail = "", subject="") =
    mkerror(ParsePhase, ERR_ConstrOr, UInt8(code);
        token,
        detail,
        context= isempty(subject) ? ErrorSite[] : ErrorSite[ErrorSite(ParsePhase, ERR_ConstrOr, subject)]
    )

function constror_render_error(io::IO, code::OrErrCode, err::ParseError)
    if code == OR_EndOfInput
        print(io, "Expected an option or command, got end of input")
    elseif code == OR_UnexpectedToken
        print(io, "Unexpected option or subcommand: $(err.token)")
    elseif code == OR_Conflict
        print(io, "$(err.detail) and $(err.token) can't be used together")
    elseif code == OR_NoMatch
        print(io, "No matching option or command")
    elseif code == OR_Unreachable
        print(io, "Internal error: reached an unreachable or-branch state")
    else
        print(io, "unreachable")
    end
end

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

# General loop logic
# for branch in branches
#     result = parse(branch, ctx)

#     if semantic success
#         return result_as_selected_branch

#     elseif control-only success
#         remember it if better than current fallback

#     else
#         maybe update best_error
#     end
# end

# if have_control_fallback
#     return control_fallback
# else
#     return best_error
# end

@generated function _generated_or_parse(parsers::PTup, ctx::Context{OrState{U}}) where {PTup <: Tuple, U}
    preamble = quote
        error = ctx_haslessthan(1, ctx) ?
            InnerParseFailure(0, constror_error(OR_EndOfInput)) :
            InnerParseFailure(0, constror_error(OR_UnexpectedToken; token = ctx_peek(ctx)))
        #=A control-only success (for example consuming `--`) should not select an
        `or` branch immediately. We keep it around as a fallback in case no
        semantic branch match is found.=#
        control_result = nothing
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

            result = (@unionsplit parse(parser, childctx))::InnerParseResult{tstate(parser)}
            if !is_error(result) && length(unwrap(result).consumed) > 0
                parse_ok = unwrap(result)

                if !parse_ok.counts_as_match
                    #=The child parser succeeded, but not in a way that should count
                    as a semantic match for this `or`. Keep the propagated context
                    and continue looking for a real branch match.=#

                    if has_selection && (selected_state isa OrBranchState{$i, $child_parser_tstate})
                        #=We are already inside this same branch. Preserve that
                        selection while surfacing the control-side-effect.=#
                        new_innerstate = some(InnerOrState{$U}(OrBranchState{$i, $child_parser_tstate}(parse_ok)))
                        newctx = widen_restate(OrState{$U}, ℒ_nextctx(parse_ok), new_innerstate)
                        control_result = innerOk(newctx, ℒ_consumed(parse_ok), false)
                    elseif !has_selection
                        #=No branch has been selected yet. Propagate the updated
                        context, but leave the `or` state unselected so later
                        branches still get a chance to match semantically.=#
                        control_result = innerOk(
                            ctx_with_state(ℒ_nextctx(parse_ok), ℒ_state(ctx)),
                            ℒ_consumed(parse_ok),
                            false
                        )
                    end
                else

                    #=If we successfully match something, but the current state is telling us that we've already matched
                    # something else,
                    # and those two things aren't the same thing, then error. 'Or' only matches one parser.=#

                    if has_selection && !(selected_state isa OrBranchState{$i, $child_parser_tstate})
                        return innerErr(ctx,
                            constror_error(
                                OR_Conflict;
                                token = parse_ok.consumed[1],
                                detail = string(selected_state.success.consumed[1])
                            );
                            consumed=ctx_length(ctx) - ctx_length(ℒ_nextctx(parse_ok))
                        )
                    end

                    new_innerstate = some(InnerOrState{$U}(OrBranchState{$i, $child_parser_tstate}(parse_ok)))
                    newctx = widen_restate(OrState{$U}, ℒ_nextctx(parse_ok), new_innerstate)
                    return innerOk(newctx, ℒ_consumed(parse_ok))
                end
            elseif is_error(result)
                if ℒ_consumed(error) < ℒ_consumed(unwrap_error(result))
                    error = unwrap_error(result)
                end
            end
        end)

    end

    epilogue = quote
        #=If nothing matched semantically, but a child parser propagated a
        control-only success, return that instead of the raw parse error.=#
        !isnothing(control_result) && return control_result
        return innerErr(ctx, error)
    end

    return quote
        $preamble
        $unrolled_loop
        $epilogue
    end
end

parse(p::ConstrOr{T, OrState{U}}, ctx::Context{OrState{U}}) where {T,U} = let

    innerstate_U = _or_inner_branch_union(typeof(p.parsers))

    convert(InnerParseResult{OrState{innerstate_U}}, _generated_or_parse(p.parsers, ctx))
end

function complete(p::ConstrOr{T}, orstate::OrState{U})::ParseResult{T} where {T, U}
    is_error(orstate) &&
        return typedErr(T, constror_error(OR_NoMatch))

    selected = unwrapunion(unwrap(orstate))::U
    return _gencomplete(p, selected)
end

@generated function _gencomplete(
        p::ConstrOr{T, OrState{U}, pprio, PTup},
        selected::U,
    )::ParseResult{T} where {T, U, pprio, PTup <: Tuple}
    ex = Expr(:block)

    for branch_t in Base.uniontypes(U)
        branch_t <: OrBranchState || continue

        i = branch_t.parameters[1]
        ptype = fieldtype(PTup, i)
        out_t = tval(ptype)

        push!(ex.args, quote
            if selected isa $branch_t
                child_result = complete(p.parsers[$i], ℒ_nextstate(selected.success))::ParseResult{$out_t}
                if is_error(child_result)
                    return typedErr(T,
                        error_with_context(child_result,
                            CompletePhase,
                            ERR_ConstrOr,
                            "or"
                        )
                    )
                end
                return typedOk(T, unwrap(child_result)::T)
            end
        end)
    end

    push!(ex.args, :(return typedErr(T, constror_error(OR_Unreachable))))
    return ex
end
