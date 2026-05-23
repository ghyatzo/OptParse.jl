const MultipleState{X} = Vector{X}

@enum MultipleErrCode::UInt8 begin
    MULTIPLE_TooFew
    MULTIPLE_TooMany
end

struct ModMultipleError <: AbstractParseError
    code::MultipleErrCode
    expected::Int
    got::Int
end

function render_error(io::IO, err::ModMultipleError)
    return if err.code == MULTIPLE_TooFew
        print(io, "Expected at least $(err.expected) values, but got only $(err.got)")
    elseif err.code == MULTIPLE_TooMany
        print(io, "Expected at most $(err.expected) values, but got $(err.got)")
    else
        print(io, "unreachable")
    end
end

struct ModMultiple{T, E, S, P, R} <: AbstractParser{T, E, S, P, R}
    initialState::S
    parser::P
    #
    min::Int
    max::Int

    ModMultiple(parser::P; min::Integer = 0, max::Integer = typemax(Int)) where {P <: AbstractParser} = let
        new{
            Vector{tval(P)},
            Union{ModMultipleError, terr(P)},
            MultipleState{tstate(P)},
            P,
            priority(P),
        }(tstate(P)[], parser, min, max)
    end
end


@autospecialize p usage(p::ModMultiple) = UsageRepeat(usage(p.parser)::UsageNode, p.min, p.max)
@autospecialize p function helpentries(p::ModMultiple, rt::OverlayContext)
    # For group-like children, keep the child entries unchanged.
    child = p.parser
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
@autospecialize p ctx function focused_helpdoc(
        p::ModMultiple{<:Any, <:Any, MultipleState{S}},
        ctx::Context{MultipleState{S}},
        prefix::Vector{String},
        rt::OverlayContext
    )::HelpDoc where {S}
    child_state = isempty(ctx_state(ctx)) ? p.parser.initialState : ctx_state(ctx)[end]
    child_ctx = widen_restate(S, ctx, child_state)
    # Behavioural modifiers do not introduce a new help scope, so node-local
    # overlay information still belongs to the wrapped parser.
    child_focus = focused_helpdoc(p.parser, child_ctx, prefix, rt)::HelpDoc

    child_focus.prefix != prefix && return child_focus
    return HelpDoc(prefix, UsageRepeat(child_focus.usage, p.min, p.max), rt.info, HelpEntry[])
end

@autospecialize p ctx function parse(p::ModMultiple{T, E, S}, ctx::Context{S}) where {T, E, S <: MultipleState}
    IS = tstate(typeof(p.parser))

    current_ctx = ctx
    allconsumed = Consumed[]
    has_active = !isempty(ctx_state(ctx))

    child_state = has_active ? ctx_state(ctx)[end] : p.parser.initialState
    child_ctx = widen_restate(IS, current_ctx, child_state)
    result = parse(p.parser, child_ctx)

    if !is_error(result)
        parse_ok = unwrap(result)
        push!(allconsumed, res_consumed(parse_ok))

        if res_matchcounts(parse_ok)
            nextst = [s for s in ctx_state(ctx)]
            if has_active
                nextst[end] = ℒ_nextstate(parse_ok)
            else
                push!(nextst, ℒ_nextstate(parse_ok))
            end

            nextctx = widen_restate(MultipleState{IS}, res_nextctx(parse_ok), nextst)
            return InnerParseResult{S, E}(innerOk(nextctx, merge(allconsumed)))
        else
            current_ctx = ctx_with_state(res_nextctx(parse_ok), ctx_state(current_ctx))
        end
    elseif !has_active
        hasconsumed = !iszero(res_num_consumed(result))
        return hasconsumed ?
            InnerParseResult{S, E}(innerErr(E, result)) : InnerParseResult{S, E}(innerOk(current_ctx, consumed_empty(current_ctx); counts_as_match = false))
    end

    if has_active && length(ctx_state(ctx)) < p.max
        child_ctx = widen_restate(IS, current_ctx, p.parser.initialState)
        retry = parse(p.parser, child_ctx)

        if is_error(retry)
            if !isempty(allconsumed)
                return InnerParseResult{S, E}(innerOk(current_ctx, merge(allconsumed); counts_as_match = false))
            end
            return InnerParseResult{S, E}(innerErr(E, retry))
        end

        parse_ok = unwrap(retry)
        push!(allconsumed, res_consumed(parse_ok))

        if res_matchcounts(parse_ok)
            nextst = [s for s in ctx_state(current_ctx)]
            push!(nextst, ℒ_nextstate(parse_ok))

            nextctx = widen_restate(MultipleState{IS}, res_nextctx(parse_ok), nextst)
            return InnerParseResult{S, E}(innerOk(nextctx, merge(allconsumed)))
        else
            current_ctx = ctx_with_state(res_nextctx(parse_ok), ctx_state(current_ctx))
            return InnerParseResult{S, E}(innerOk(current_ctx, merge(allconsumed); counts_as_match = false))
        end
    end

    consumed = isempty(allconsumed) ? consumed_empty(current_ctx) : merge(allconsumed)
    return InnerParseResult{S, E}(innerOk(current_ctx, consumed; counts_as_match = false))

end

@autospecialize p function complete(p::ModMultiple{T, E, S}, state::S) where {T, E, S <: MultipleState}
    IT = tval(typeof(p.parser))
    IE = terr(typeof(p.parser))

    result = IT[]
    for s in state
        val = complete(p.parser, s)
        if is_error(val)
            return ParseResult{T, E}(typedErr(E, unwrap_error(val)))
        end
        val = unwrap(val)
        push!(result, val)
    end

    if length(result) < p.min
        return ParseResult{T, E}(typedErr(E,
            ModMultipleError(MULTIPLE_TooFew, p.min, length(result))
        ))
    elseif length(result) > p.max
        return ParseResult{T, E}(typedErr(E,
            ModMultipleError(MULTIPLE_TooMany, p.max, length(result))
        ))
    end

    return ParseResult{T, E}(typedOk(T, result))

end
