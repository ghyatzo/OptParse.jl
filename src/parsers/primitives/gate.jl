const GateState = ParseResult{Bool}

@enum GateErrCode::UInt8 begin
    GATE_NoMoreOptions
    GATE_EndOfInput
    GATE_Duplicate
    GATE_NoMatch
    GATE_Missing
end

arggate_error(code::GateErrCode; token = "", detail = "", subject = "") =
    mkerror(
    ParsePhase, ERR_ArgGate, UInt8(code);
    token,
    detail,
    trace = isempty(subject) ? ErrorSite[] : ErrorSite[ErrorSite(ParsePhase, ERR_ArgGate, subject)]
)

function arggate_render_error(io::IO, code::GateErrCode, err::ParseError)
    return if code == GATE_NoMoreOptions
        print(io, "No more options can be parsed")
    elseif code == GATE_EndOfInput
        print(io, "Expected a flag, got end of input")
    elseif code == GATE_Duplicate
        print(io, "Flag $(err.token) cannot be used multiple times")
    elseif code == GATE_NoMatch
        print(io, "Unexpected flag: $(err.token)")
    elseif code == GATE_Missing
        print(io, "Missing required flag(s): $(err.detail)")
    else
        print(io, "unreachable")
    end
end

# single boolean flags: -q --long
struct ArgGate{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    _dummy::P
    #
    names::Vector{String}


    ArgGate(names::Tuple{Vararg{String}}) = begin
        for name in names
            if !startswith(name, r"^--?[^-]")
                throw(ArgumentError("Flags and option names must start with `-` or `--`."))
            end
            if startswith(name, r"^-[^-]") && length(name) > 2
                throw(ArgumentError("Short options and flags must only have 1 character."))
            end

        end
        new{Bool, GateState, 9, Nothing}(typedErr(arggate_error(GATE_Missing; detail = "$(names)")), nothing, [names...])
    end
end

usage(p::ArgGate) = UsageFlag(p.names)
helpentries(p::ArgGate, rt::OverlayContext) = [HelpEntry(usage(p), helpinfo(rt))]
focused_helpdoc(
    p::ArgGate,
    ctx::Context{GateState},
    prefix::Vector{String},
    rt::OverlayContext
) = HelpDoc(prefix, usage(p), helpinfo(rt), HelpEntry[])

function parse(p::ArgGate{Bool, GateState}, ctx::Context{GateState})::InnerParseResult{GateState}

    if ctx_optterm(ctx)
        return innerErr(ctx, arggate_error(GATE_NoMoreOptions))
    elseif ctx_hasnone(ctx)
        return innerErr(ctx, arggate_error(GATE_EndOfInput))
    end

    tok = ctx_peek(ctx)

    #= When the input contains `--` stop parsing options =#
    if (tok === "--")
        return innerOk(
            ctx, 1;
            nextctx = ctx_with_options_terminated(consume(ctx, 1), true),
            counts_as_match = false
        )
    end

    if tok in p.names

        if !is_error(ctx_state(ctx)) && unwrap(ctx_state(ctx))
            return innerErr(ctx, arggate_error(GATE_Duplicate; token = tok); consumed = 1)
        end

        nextctx = ctx_with_state(consume(ctx, 1), GateState(typedOk(true)))
        return innerOk(ctx, 1; nextctx)
    end

    return innerErr(ctx, arggate_error(GATE_NoMatch; token = tok))
end

function complete(p::ArgGate, st::GateState)::ParseResult{Bool}
    return !is_error(st) ? st : typedErr(
            error_with_trace(
                st,
                CompletePhase,
                ERR_ArgGate,
                p.names[1]
            )
        )
end
