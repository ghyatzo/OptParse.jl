@wrapped struct InnerOrState{U}
    union::U
end

struct OrBranchState{I, S}
    success::InnerParseSuccess{S}
end

branch_idx(::Type{OrBranchState{I, S}}) where {I, S} = I
branch_state(::Type{OrBranchState{I, S}}) where {I, S} = S

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
                :(append!(entries, helpentries(p.parsers[$i], descend_child(rt))::Vector{HelpEntry}))
            )
        end
        push!(ex.args, :(return entries))
        return ex
    else
        entries = HelpEntry[]
        for (child, type) in zip(values(p.parsers), fieldtypes(PTup))
            append!(entries, helpentries(child::type, descend_child(rt))::Vector{HelpEntry})
        end
        return entries
    end

end

@inline function focused_helpdoc(
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

    selected = unwrap(ctx_state(ctx))
    # we unionsplit on the selected branch
    return @unionsplit _focused_helpdoc_or(p, selected, prefix, rt)
end

function _focused_helpdoc_or(
        p::ConstrOr, selected::OrBranchState{I, S}, prefix::Vector{String}, rt::OverlayContext
    )::HelpDoc where {I, S}
    # then recurse into the selected child pareser
    return focused_helpdoc(p.parsers[I], res_nextctx(selected.success), prefix, descend_child(rt))
end

# @generated function _generated_or_parse(parsers::PTup, ctx::Context{OrState{U}}) where {PTup <: Tuple, U}
#     #=
#     # General loop logic
#     #
#     # current_ctx starts as the original parse context. Unlike a normal branch match,
#     # a control-only success (for example consuming `--`) should not select an `or`
#     # branch, but it *should* mutate the running context for the rest of the search.
#     # This means that later branches are tried against the updated context.
#     #
#     # for branch in branches
#     #     result = parse(branch, current_ctx)
#     #
#     #     if semantic success
#     #         record branch selection
#     #         merge any previously consumed control tokens
#     #         return selected result
#     #
#     #     elseif control-only success
#     #         update current_ctx
#     #         accumulate consumed control tokens
#     #         continue trying later branches
#     #
#     #     else
#     #         maybe update best_error
#     #     end
#     # end
#     #
#     # if current_ctx changed
#     #     return control-only success with accumulated consumption
#     # else
#     #     return best_error
#     # end
#     =#


@autospecialize p selected currctx function _parse_branch(
        p::ConstrOr{T, <:OrState{U}}, selected::OrBranchState{I, S}, currctx::Context{OrState{U}},
        allconsumed::Vector{Consumed}, error::InnerParseFailure
    ) where {T, U, I, S}

    child_state = ℒ_nextstate(selected.success)
    child_ctx = ctx_with_state(currctx, child_state)

    result = parse(p.parsers[I], child_ctx)
    if !is_error(result) && res_num_consumed(result) > 0
        parse_ok = unwrap(result)

        new_innerstate = some(InnerOrState{U}(OrBranchState{I, S}(parse_ok)))
        newctx = widen_restate(OrState{U}, res_nextctx(parse_ok), new_innerstate)
        push!(allconsumed, res_consumed(parse_ok))

        if !parse_ok.counts_as_match
            #=The child parser succeeded, but not in a way that should count
            as a semantic match for this `or`. Propagate the updated
            context and keep looking for a real branch match.=#

            #=We are already inside this same branch. Preserve that
            selection while surfacing the control-side-effect.=#
            if newctx != currctx
                return innerOk(newctx, merge(allconsumed), false)
            else
                return innerErr(newctx, error)
            end
        else
            return innerOk(newctx, merge(allconsumed))
        end
    elseif is_error(result)
        #= the child parser has encountered an error, we should resurface that error instead of the generic =#
        error = error_with_trace(
            result, ParsePhase, ERR_ConstrOr, "or"
        )
    end

    return innerErr(currctx, error)
end

# _or_parse_impl is provided by static/or.jl or dynamic/or.jl
# parse and complete are provided by static/or.jl or dynamic/or.jl
