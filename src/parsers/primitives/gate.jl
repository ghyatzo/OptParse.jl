const GateState = ParseResult{Bool}

@enum GateErrCode::UInt8 begin
    GATE_NoMoreOptions
    GATE_EndOfInput
    GATE_Duplicate
    GATE_NoMatch
    GATE_Missing
end

struct ArgGateError <: AbstractParseError
    code::GateErrCode
    token::String
    detail::String
end

function render_error(io::IO, err::ArgGateError)
    return if err.code == GATE_NoMoreOptions
        print(io, "No more options can be parsed")
    elseif err.code == GATE_EndOfInput
        print(io, "Expected a flag, got end of input")
    elseif err.code == GATE_Duplicate
        print(io, "Flag $(err.token) cannot be used multiple times")
    elseif err.code == GATE_NoMatch
        print(io, "Unexpected flag: $(err.token)")
    elseif err.code == GATE_Missing
        print(io, "Missing required flag(s): $(err.detail)")
    else
        print(io, "unreachable")
    end
end

# single boolean flags: -q --long
struct ArgGate{T, E, S, P, R} <: AbstractParser{T, E, S, P, R}
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
        new{Bool, Nothing, GateState, Nothing, 9}(
            typedErr(parse_error(ArgGateError(GATE_Missing, "", "$(names)"))), 
            nothing, 
            [names...]
        )
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

function parse(p::ArgGate{Bool, <:Any, GateState}, ctx::Context{GateState})::InnerParseResult{GateState}

    if ctx_optterm(ctx)
        return innerErr(ctx, ArgGateError(GATE_NoMoreOptions, "", ""))
    elseif ctx_hasnone(ctx)
        return innerErr(ctx, ArgGateError(GATE_EndOfInput, "", ""))
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

        if !is_error(ctx_state(ctx))
            return innerErr(ctx, ArgGateError(GATE_Duplicate, tok, ""); consumed = 1)
        end

        nextctx = ctx_with_state(consume(ctx, 1), GateState(typedOk(true)))
        return innerOk(ctx, 1; nextctx)
    end

    return innerErr(ctx, ArgGateError(GATE_NoMatch, tok, ""))
end

function complete(p::ArgGate, st::GateState)::ParseResult{Bool}
    return !is_error(st) ? st : typedErr(unwrap_error(st))
end
