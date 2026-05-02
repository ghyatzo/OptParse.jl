const MultipleState{X} = Vector{X}

@enum MultipleErrCode::UInt8 begin
    MULTIPLE_TooFew
    MULTIPLE_TooMany
end

modmultiple_error(code::MultipleErrCode; token = "", detail = "", subject = "") =
    mkerror(
    CompletePhase, ERR_ModMultiple, UInt8(code);
    token,
    detail,
    trace = isempty(subject) ? ErrorSite[] : ErrorSite[ErrorSite(CompletePhase, ERR_ModMultiple, subject)]
)

function modmultiple_render_error(io::IO, code::MultipleErrCode, err::ParseError)
    return if code == MULTIPLE_TooFew
        min, got = split(err.detail, ","; limit = 2)
        print(io, "Expected at least $(min) values, but got only $(got)")
    elseif code == MULTIPLE_TooMany
        max, got = split(err.detail, ","; limit = 2)
        print(io, "Expected at most $(max) values, but got $(got)")
    else
        print(io, "unreachable")
    end
end

struct ModMultiple{T, S, _p, P} <: AbstractParser{T, S, _p, P}
    initialState::S
    parser::P
    #
    min::Int
    max::Int
end

ModMultiple(parser::P; min::Integer = 0, max::Integer = typemax(Int)) where {P <: AbstractParser} = let
    ModMultiple{
        Vector{tval(P)},
        MultipleState{tstate(P)},
        priority(P),
        P,
    }(tstate(P)[], parser, min, max)
end

usage(p::ModMultiple) = UsageRepeat(usage(p.parser)::UsageNode, p.min, p.max)
function helpentries(p::ModMultiple, rt::OverlayContext)
    # For group-like children, keep the child entries unchanged.
    child = unwrapunion(p.parser)
    return if (
            child isa ArgGate
                || child isa ArgOption
                || child isa ArgConstant
                || child isa ArgArgument
                || child isa ArgCommand
        )

        entry = helpentries(child, rt)[1]
        HelpEntry[set(entry, (@o _.usage), UsageRepeat(entry.usage, p.min, p.max))]
    else
        helpentries(child, rt)
    end
end
function focused_helpdoc(
        p::ModMultiple{T, MultipleState{S}},
        ctx::Context{MultipleState{S}},
        prefix::Vector{String},
        rt::OverlayContext
    )::HelpDoc where {T, S}
    child_state = isempty(ctx_state(ctx)) ? p.parser.initialState : ctx_state(ctx)[end]
    child_ctx = widen_restate(S, ctx, child_state)
    # Behavioural modifiers do not introduce a new help scope, so node-local
    # overlay information still belongs to the wrapped parser.
    child_focus = focused_helpdoc(p.parser, child_ctx, prefix, rt)

    child_focus.prefix != prefix && return child_focus
    return HelpDoc(prefix, UsageRepeat(child_focus.usage, p.min, p.max), rt.info, HelpEntry[])
end

function parse(p::ModMultiple{T, MultipleState{S}}, ctx::Context{MultipleState{S}})::InnerParseResult{MultipleState{S}} where {T, S}

    #=Conceptual map:

	`multiple` stores the child parse state for each matched repetition in `state`.

	On each parse step it tries, in order:

	1. continue the currently active repetition, if one exists
	2. if that does not produce a semantic match, try to start a fresh repetition

	With `counts_as_match`, a child parse can now succeed in two different ways:

	- semantic match:
	  the child really matched one repetition item
	- control-only success:
	  the child consumed input only to propagate parser-global context
	  (currently this mainly means consuming `--`)

	Control-only successes must propagate the updated context, but they must *not*
	create a repetition, satisfy one, or overwrite an existing repetition state.

	`current_ctx` carries those propagated context changes across the attempts.
	`allconsumed` keeps every consumed chunk so the returned `Consumed` reflects
	the whole parse step, not only the final child attempt.
	=#
    current_ctx = ctx
    allconsumed = Consumed[]
    has_active = !isempty(ctx_state(ctx))

    #=First attempt:
	continue the active repetition if one exists;
	otherwise try to start the first repetition.=#
    child_state = has_active ? ctx_state(ctx)[end] : p.parser.initialState
    child_ctx = widen_restate(S, current_ctx, child_state)
    result = parse(unwrapunion(p.parser), child_ctx)::InnerParseResult{S}

    if !is_error(result)
        parse_ok = unwrap(result)
        push!(allconsumed, res_consumed(parse_ok))

        if res_matchcounts(parse_ok)
            #=The child matched semantically.
			This either updates the active repetition or creates the first one.=#
            nextst = [s for s in ctx_state(ctx)]
            if has_active
                nextst[end] = ℒ_nextstate(parse_ok)
            else
                push!(nextst, ℒ_nextstate(parse_ok))
            end

            nextctx = widen_restate(MultipleState{S}, res_nextctx(parse_ok), nextst)
            return innerOk(nextctx, merge(allconsumed))
        else
            #=The child only propagated control state.
			Carry the updated parsing context forward, but do not alter the
			repetition structure yet.=#
            current_ctx = ctx_with_state(res_nextctx(parse_ok), ctx_state(current_ctx))
        end
    elseif !has_active
        hasconsumed = !iszero(res_num_consumed(result))
        #=If there is no active repetition yet, a consuming failure on the first
			attempt is final: there is no current repetition to close and no second
			chance to reinterpret the same token as the start of a new repetition.
			A non-consuming failure simply means that no repetition starts here.=#
        return hasconsumed ?
            innerErr(ctx, result) : innerOk(current_ctx, consumed_empty(current_ctx), false)
    end

    #=Second attempt:
	if there was already an active repetition, the first attempt may have failed
	only because that repetition has finished. Reset the child to a blank slate
	and see whether the same input starts a new repetition instead.
	But only if we haven't reached the maximum allowed number of matches already.=#
    if has_active && length(ctx_state(ctx)) < p.max
        child_ctx = widen_restate(S, current_ctx, p.parser.initialState)
        retry = parse(unwrapunion(p.parser), child_ctx)::InnerParseResult{S}

        if is_error(retry)
            #=No new repetition started either.
			If we consumed input only to propagate control state, bubble that
			progress outward; otherwise the failure is real.=#
            if !isempty(allconsumed)
                return innerOk(current_ctx, merge(allconsumed), false)
            end
            return innerErr(ctx, retry)
        end

        parse_ok = unwrap(retry)
        push!(allconsumed, res_consumed(parse_ok))

        if res_matchcounts(parse_ok)
            #=A fresh repetition matched semantically. Append it to the state.=#
            nextst = [s for s in ctx_state(current_ctx)]
            push!(nextst, ℒ_nextstate(parse_ok))

            nextctx = widen_restate(MultipleState{S}, res_nextctx(parse_ok), nextst)
            return innerOk(nextctx, merge(allconsumed))
        else
            #=A fresh parse attempt also only propagated control state.
			Update context, but do not append a repetition.=#
            current_ctx = ctx_with_state(res_nextctx(parse_ok), ctx_state(current_ctx))
            return innerOk(current_ctx, merge(allconsumed), false)
        end
    end

    #=No semantic repetition matched, but control state did propagate.
	Bubble that progress outward so outer parsers see the updated context.=#
    consumed = isempty(allconsumed) ? consumed_empty(current_ctx) : merge(allconsumed)
    return innerOk(current_ctx, consumed, false)

end

function complete(p::ModMultiple{T, MultipleState{S}, _p, P}, state::MultipleState{S})::ParseResult{T} where {T, S, _p, P}
    result = tval(P)[]
    for s in state
        val = complete(unwrapunion(p.parser), s)::ParseResult{tval(p.parser)}
        if is_error(val)
            return typedErr(
                T,
                error_with_trace(
                    val,
                    CompletePhase,
                    ERR_ModMultiple,
                    "multiple"
                )
            )
        end
        val = unwrap(val)
        push!(result, val)
    end

    if length(result) < p.min
        return typedErr(
            T, modmultiple_error(
                MULTIPLE_TooFew; detail = "$(p.min),$(length(result))"
            )
        )
    elseif length(result) > p.max
        return typedErr(
            T, modmultiple_error(
                MULTIPLE_TooMany; detail = "$(p.max),$(length(result))"
            )
        )
    end

    return typedOk(T, result)

end
