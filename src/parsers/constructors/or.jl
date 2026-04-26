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

constror_error(code::OrErrCode; token = "", detail = "", subject = "") =
    mkerror(
    ParsePhase, ERR_ConstrOr, UInt8(code);
    token,
    detail,
    trace = isempty(subject) ? ErrorSite[] : ErrorSite[ErrorSite(ParsePhase, ERR_ConstrOr, subject)]
)

function constror_render_error(io::IO, code::OrErrCode, err::ParseError)
    return if code == OR_EndOfInput
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

@inline usage(p::ConstrOr) = UsageAlternative(_usage_children(p.parsers))
function helpentries(p::ConstrOr{T, S, _p, PTup}, rt::OverlayContext) where {T, S <: OrState, _p, PTup <: Tuple}

    if @generated
        ex = quote
            entries = HelpEntry[]
        end
        for (i, type) in enumerate(fieldtypes(PTup))
            push!(
                ex.args,
                :(append!(entries, @unionsplit helpentries(p.parsers[$i], descend_child(rt))::Vector{HelpEntry}))
            )
        end
        push!(ex.args, :(return entries))
        return ex
    else
        entries = HelpEntry[]
        for (child, type) in zip(values(p.parsers), fieldtypes(PTup))
            append!(entries, @unionsplit helpentries(child::type, descend_child(rt))::Vector{HelpEntry})
        end
        return entries
    end
end
function focused_helpdoc(
        p::ConstrOr{T, OrState{U}},
        ctx::Context{OrState{U}},
        prefix::Vector{String},
        rt::OverlayContext
    )::HelpDoc where {T, U}
    is_error(ctx_state(ctx)) && return HelpDoc(
        prefix,
        usage(p),
        helpinfo(rt),
        helpentries(p, descend_child(rt))::Vector{HelpEntry}
    )

    selected = unwrapunion(unwrap(ctx_state(ctx)))::U
    return _focused_helpdoc_or(p, selected, prefix, rt)
end

@generated function _focused_helpdoc_or(
        p::ConstrOr{T, OrState{U}, pprio, PTup},
        selected::U,
        prefix::Vector{String},
        rt::OverlayContext
    )::HelpDoc where {T, U, pprio, PTup <: Tuple}
    body = Expr(:block)

    for branch_t in Base.uniontypes(U)
        branch_t <: OrBranchState || continue

        i = branch_t.parameters[1]
        push!(
            body.args, quote
                if selected isa $branch_t
                    return focused_helpdoc(p.parsers[$i], res_nextctx(selected.success), prefix, descend_child(rt))
                end
            end
        )
    end

    # TODO: Also here is wrong.
    push!(body.args, :(return HelpDoc(prefix, usage(p), helpinfo(rt), @unionsplit helpentries(p, descend_child(rt)))))
    return body
end

@generated function _generated_or_parse(parsers::PTup, ctx::Context{OrState{U}}) where {PTup <: Tuple, U}
    #=
    # General loop logic
    #
    # current_ctx starts as the original parse context. Unlike a normal branch match,
    # a control-only success (for example consuming `--`) should not select an `or`
    # branch, but it *should* mutate the running context for the rest of the search.
    # This means that later branches are tried against the updated context.
    #
    # for branch in branches
    #     result = parse(branch, current_ctx)
    #
    #     if semantic success
    #         record branch selection
    #         merge any previously consumed control tokens
    #         return selected result
    #
    #     elseif control-only success
    #         update current_ctx
    #         accumulate consumed control tokens
    #         continue trying later branches
    #
    #     else
    #         maybe update best_error
    #     end
    # end
    #
    # if current_ctx changed
    #     return control-only success with accumulated consumption
    # else
    #     return best_error
    # end
    =#
    preamble = quote
        error = ctx_haslessthan(1, ctx) ?
            InnerParseFailure(0, constror_error(OR_EndOfInput)) :
            InnerParseFailure(0, constror_error(OR_UnexpectedToken; token = ctx_peek(ctx)))
        #=Control-only successes should update the running parse context without
        selecting a branch. This is needed for things like `--`, which changes
        the global parsing mode but is not itself a semantic branch match.=#
        current_ctx = ctx
        allconsumed = Consumed[consumed_empty(ctx)]
    end
    N = fieldcount(PTup)
    unrolled_loop = Expr(:block)

    for i in 1:N
        child_parser_t = fieldtype(PTup, i)
        child_parser_tstate = tstate(child_parser_t)

        push!(
            unrolled_loop.args, quote
                parser = parsers[$i]::$child_parser_t
                innerstate = ctx_state(current_ctx)
                has_selection = !is_error(innerstate)
                selected_state = has_selection ? unwrapunion(unwrap(innerstate)) : nothing

                #=Once an `or` branch has been selected, it stays selected.
            Subsequent parse steps must keep feeding that same branch rather
            than letting the other branches compete again.=#
                if !has_selection || (selected_state isa OrBranchState{$i, $child_parser_tstate})
                    childstate = has_selection ?
                        ℒ_nextstate(selected_state.success)::$child_parser_tstate :
                        parser.initialState
                    childctx = ctx_with_state(current_ctx, childstate)

                    result = (@unionsplit parse(parser, childctx))::InnerParseResult{tstate(parser)}
                    if !is_error(result) && length(unwrap(result).consumed) > 0
                        parse_ok = unwrap(result)

                        if !parse_ok.counts_as_match
                            #=The child parser succeeded, but not in a way that should count
                        as a semantic match for this `or`. Propagate the updated
                        context and keep looking for a real branch match.=#

                            if has_selection
                                #=We are already inside this same branch. Preserve that
                            selection while surfacing the control-side-effect.=#
                                new_innerstate = some(InnerOrState{$U}(OrBranchState{$i, $child_parser_tstate}(parse_ok)))
                                newctx = widen_restate(OrState{$U}, res_nextctx(parse_ok), new_innerstate)
                                push!(allconsumed, res_consumed(parse_ok))
                                current_ctx = newctx
                            else
                                #=No branch has been selected yet. Propagate the updated
                            context, but leave the `or` state unselected so later
                            branches still get a chance to match semantically.=#
                                push!(allconsumed, res_consumed(parse_ok))
                                current_ctx = ctx_with_state(res_nextctx(parse_ok), ctx_state(current_ctx))
                            end
                        else
                            new_innerstate = some(InnerOrState{$U}(OrBranchState{$i, $child_parser_tstate}(parse_ok)))
                            newctx = widen_restate(OrState{$U}, ℒ_nextctx(parse_ok), new_innerstate)
                            push!(allconsumed, res_consumed(parse_ok))
                            return innerOk(newctx, merge(allconsumed))
                        end
                    elseif is_error(result)
                        if has_selection
                            #= the child parser has encountered an error, we should resurface that error instead of the generic =#
                            error = error_with_trace(
                                result,
                                ParsePhase,
                                ERR_ConstrOr,
                                "or"
                            )
                        elseif res_num_consumed(error) < res_num_consumed(result)
                            error = unwrap_error(result)
                        end
                    end
                end
            end
        )
    end

    epilogue = quote
        if current_ctx != ctx
            return innerOk(current_ctx, merge(allconsumed), false)
        end
        return innerErr(current_ctx, error)
    end

    return quote
        $preamble
        $unrolled_loop
        $epilogue
    end
end

parse(p::ConstrOr{T, OrState{U}}, ctx::Context{OrState{U}}) where {T, U} = let

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

        push!(
            ex.args, quote
                if selected isa $branch_t
                    child_result = (@unionsplit complete(p.parsers[$i], ℒ_nextstate(selected.success)))::ParseResult{$out_t}
                    if is_error(child_result)
                        return typedErr(
                            T,
                            error_with_trace(
                                child_result,
                                CompletePhase,
                                ERR_ConstrOr,
                                "or"
                            )
                        )
                    end
                    return typedOk(T, unwrap(child_result)::T)
                end
            end
        )
    end

    push!(ex.args, :(return typedErr(T, constror_error(OR_Unreachable))))
    return ex
end
