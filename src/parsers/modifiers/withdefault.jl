const WithDefaultState{X} = Option{X}

@enum WithDefaultErrCode::UInt8 begin
    WITHDEFAULT_DummyError
end

modwithdefault_error(code::WithDefaultErrCode; token = "", detail = "", subject = "") =
    mkerror(
    CompletePhase, ERR_ModWithDefault, UInt8(code);
    token,
    detail,
    trace = isempty(subject) ? ErrorSite[] : ErrorSite[ErrorSite(CompletePhase, ERR_ModWithDefault, subject)]
)

function modwithdefault_render_error(io::IO, code::WithDefaultErrCode, err::ParseError)
    return if code == WITHDEFAULT_DummyError
        print(io, "default internal error")
    else
        print(io, "unreachable")
    end
end

struct ModWithDefault{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    parser::P
    #
    default::T

    ModWithDefault(parser::P, default::T) where {T, P} = let
        retval_t = tval(P) == T ? T : Union{tval(P), T}
        new{retval_t, WithDefaultState{tstate(P)}, priority(P), P}(none(tstate(P)), parser, default)
    end
end

usage(p::ModWithDefault) = UsageOptional(usage(p.parser))
function helpentries(p::ModWithDefault, rt::OverlayContext)
    child = unwrapunion(p.parser)
    return if (
            child isa ArgGate
                || child isa ArgOption
                || child isa ArgConstant
                || child isa ArgArgument
                || child isa ArgCommand
        )

        entry = helpentries(child, rt)[1]
        HelpEntry[set(entry, (@o _.usage), UsageOptional(entry.usage))]
    else
        helpentries(child, rt)
    end
end
function focused_helpdoc(
        p::ModWithDefault{T, WithDefaultState{S}, _p, P},
        ctx::Context{WithDefaultState{S}},
        prefix::Vector{String},
        rt::OverlayContext
    )::HelpDoc where {T, S, _p, P <: AbstractParser{<:Any, S}}
    child_state = is_error(ctx_state(ctx)) ? p.parser.initialState : unwrap(ctx_state(ctx))
    child_ctx = widen_restate(S, ctx, child_state)
    # we don't reset the OverlayContext because the modifiers are sort of "behavioural overlays"
    # so they can't consume the node local informations.
    child_focus = @unionsplit focused_helpdoc(p.parser, child_ctx, prefix, rt)::HelpDoc

    child_focus.prefix != prefix && return child_focus
    return HelpDoc(prefix, UsageOptional(child_focus.usage), rt.info, HelpEntry[])
end

function parse(
        p::ModWithDefault{T, WithDefaultState{S}, _p, P},
        ctx::Context{WithDefaultState{S}}
    )::InnerParseResult{WithDefaultState{S}} where {T, S, _p, P <: AbstractParser{<:Any, S}}

    childstate = is_error(ctx_state(ctx)) ? p.parser.initialState : unwrap(ctx_state(ctx))
    childctx = ctx_with_state(ctx, childstate)

    result = parse(unwrapunion(p.parser), childctx)::InnerParseResult{S}

    if is_error(result)
        parse_err = unwrap_error(result)
        #=the inner parser failed without consuming any input, which means that it wasn't matched.=#
        if res_num_consumed(parse_err) == 0
            return innerOk(ctx, consumed_empty(ctx))
        else
            #=otherwise the parser failed midway, and that we should propagate.=#
            return innerErr(ctx, parse_err)
        end
    end

    parse_ok = unwrap(result)
    if ℒ_nextstate(parse_ok) != childstate || res_num_consumed(parse_ok) == 0
        #=Inner parser actually consumed something or changed its state=#
        newctx = ctx_restate(res_nextctx(parse_ok), some(ℒ_nextstate(parse_ok)))
    else
        #=Inner parser returned success but nothing changed while consuming input. (i.e. "--")
        Treat as unmatched, but still propagate side effects.=#
        newctx = ctx_restate(res_nextctx(parse_ok), ctx_state(ctx))
    end

    return innerOk(newctx, res_consumed(parse_ok))

end

function complete(
        p::ModWithDefault{T, WithDefaultState{S}, _p, P},
        maybestate::WithDefaultState{S}
    )::ParseResult{T} where {T, S, _p, P <: AbstractParser{<:Any, S}}

    # The state can be missing (none), in which case return the default.
    if is_error(maybestate)
        return typedOk(T, p.default)
    end
    state = unwrap(maybestate)


    #=This approach would also work, but is less conceptually correct. We're assuming that a state is a Result.
    This may lead to further headaches in the future. Instead we catch this case at parse time. (see if else on success)=#
    # The state exists but is an error.
    #state isa Result && is_error(state) && return typedOk(p.default)

    #= Otherwise just ask the inner state to complete itself.
    In case of validation errors from the value parser, we want to return an error instead of the default.
    Given that the user explicitly passed a value, he likely does not want the default value.=#
    result = complete(unwrapunion(p.parser), state)::ParseResult{tval(p.parser)}
    if is_error(result)
        return typedErr(
            T,
            error_with_trace(
                result,
                CompletePhase,
                ERR_ModWithDefault,
                "default"
            )
        )
    end

    # Rewrap as the widened output type of the modifier.
    return typedOk(T, unwrap(result)::T)
end
