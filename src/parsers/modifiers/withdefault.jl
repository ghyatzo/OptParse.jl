@sum_type WithDefaultState{X} :hidden begin
    NotMatched
    Matched{X}(state::X)
end

@inline _should_show_default(::Type{P}, ::Type{Nothing}) where {P} = false
@inline _should_show_default(::Type{<:ArgGate}, ::Type{Bool}) = false
@inline _should_show_default(::Type{P}, ::Type{T}) where {P, T} = true

struct ModWithDefault{T, E, S, P, R} <: AbstractParser{T, E, S, P, R}
    initialState::S
    parser::P
    #
    default::T
    show_default::Bool

    ModWithDefault(parser::P, default::T) where {T, P <: AbstractParser} = let
        retval_t = val_t(P) == T ? T : Union{val_t(P), T}
        new{retval_t, err_t(P), WithDefaultState{state_t(P)}, P, priority(P)}(
            WithDefaultState{state_t(P)}'.NotMatched, parser, default, _should_show_default(P, T)
        )
    end
end

@autospecialize p usage(p::ModWithDefault) = p.show_default ?
    UsageDefault(usage(p.parser), string(p.default)) :
    UsageOptional(usage(p.parser))

@autospecialize p function helpentries(p::ModWithDefault, rt::OverlayContext)
    child = p.parser
    return if (
            child isa ArgGate
                || child isa ArgOption
                || child isa ArgConstant
                || child isa ArgArgument
                || child isa ArgCommand
        )

        entry = helpentries(child, rt)[1]
        new_usage = p.show_default ?
            UsageDefault(entry.usage, string(p.default)) :
            UsageOptional(entry.usage)
        HelpEntry[@set entry.usage = new_usage]
    else
        helpentries(child, rt)
    end
end
@autospecialize p ctx function focused_helpdoc(
        p::ModWithDefault{<:Any, <:Any, WithDefaultState{S}, P},
        ctx::Context{WithDefaultState{S}},
        prefix::Vector{String},
        rt::OverlayContext
    )::HelpDoc where {S, P <: AbstractParser{<:Any, <:Any, S}}
    child_state = @cases state(ctx) begin
        NotMatched => p.parser.initialState
        Matched(st) => st
    end
    child_ctx = widen_restate(S, ctx, child_state)
    # we don't reset the OverlayContext because the modifiers are sort of "behavioural overlays"
    # so they can't consume the node local informations.
    child_focus = focused_helpdoc(p.parser, child_ctx, prefix, rt)::HelpDoc

    child_focus.prefix != prefix && return child_focus
    return HelpDoc(prefix, UsageOptional(child_focus.usage), rt.info, HelpEntry[])
end

@autospecialize p ctx function parse(
        p::ModWithDefault{<:Any, E, WithDefaultState{S}, P},
        ctx::Context{WithDefaultState{S}}
    ) where {E, S, P <: AbstractParser{<:Any, <:Any, S}}
    WDS = WithDefaultState{S}

    childstate = @cases state(ctx) begin
        NotMatched => p.parser.initialState
        Matched(st) => st
    end
    childctx = with_state(ctx, childstate)

    result = parse(p.parser, childctx)

    if is_error(result)
        #=the inner parser failed without consuming any input, which means that it wasn't matched.=#
        if res_num_consumed(result) == 0
            return InnerParseResult{WDS, E}(innerOk(ctx, consumed_empty(ctx)))
        else
            #=otherwise the parser failed midway, and that we should propagate.=#
            return InnerParseResult{WDS, E}(innerErr(E, result))
        end
    end

    parse_ok = unwrap(result)
    if res_nextstate(parse_ok) != childstate || res_num_consumed(parse_ok) == 0
        #=Inner parser actually consumed something or changed its state=#
        newctx = restate(res_nextctx(parse_ok), WDS'.Matched(res_nextstate(parse_ok)))
    else
        #=Inner parser returned success but nothing changed while consuming input. (i.e. "--")
        Treat as unmatched, but still propagate side effects.=#
        newctx = restate(res_nextctx(parse_ok), state(ctx))
    end

    return InnerParseResult{WDS, E}(innerOk(newctx, res_consumed(parse_ok)))

end

@autospecialize p function complete(
        p::ModWithDefault{T, E, WithDefaultState{S}, P},
        st::WithDefaultState{S}
    ) where {T, E, S, P <: AbstractParser{<:Any, <:Any, S}}

    childstate = @cases st begin
        NotMatched => return ParseResult{T, E}(typedOk(T, p.default))
        Matched(childstate) => childstate
    end

    result = complete(p.parser, childstate)
    if is_error(result)
        return ParseResult{T, E}(Err(unwrap_error(result)))
    end

    # Rewrap as the widened output type of the modifier.
    return ParseResult{T, E}(Ok(unwrap(result)))
end
