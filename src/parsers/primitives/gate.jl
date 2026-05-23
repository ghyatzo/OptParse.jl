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

const GateState = ParseResult{Bool, ArgGateError}

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
        new{Bool, ArgGateError, GateState, Nothing, 9}(
            ParseResult{Bool, ArgGateError}(Err(ArgGateError(GATE_Missing, "", "$(names)"))),
            nothing,
            [names...]
        )
    end
end

usage(p::ArgGate) = UsageFlag(p.names)
helpentries(p::ArgGate, rt::OverlayContext) = [HelpEntry(usage(p), helpinfo(rt))]
focused_helpdoc(
    p::ArgGate,
    ::Context{GateState},
    prefix::Vector{String},
    rt::OverlayContext
) = HelpDoc(prefix, usage(p), helpinfo(rt), HelpEntry[])

function parse(p::ArgGate{Bool, ArgGateError, S}, ctx::Context{S}) where {S <: GateState}

    if ctx_optterm(ctx)
        return InnerParseResult{S, ArgGateError}(innerErr(ArgGateError(GATE_NoMoreOptions, "", "")))
    elseif ctx_hasnone(ctx)
        return InnerParseResult{S, ArgGateError}(innerErr(ArgGateError(GATE_EndOfInput, "", "")))
    end

    tok = ctx_peek(ctx)

    #= When the input contains `--` stop parsing options =#
    if (tok === "--")
        nextctx = ctx_with_options_terminated(ctx, true)
        return InnerParseResult{S, ArgGateError}(innerOk(nextctx, 1; counts_as_match = false))
    end

    if tok in p.names

        if !is_error(ctx_state(ctx))
            return InnerParseResult{S, ArgGateError}(innerErr(ArgGateError(GATE_Duplicate, tok, ""); consumed = 1))
        end

        nextctx = ctx_with_state(ctx, ParseResult{Bool, ArgGateError}(Ok(true)))
        return InnerParseResult{S, ArgGateError}(innerOk(nextctx, 1))
    end

    return InnerParseResult{S, ArgGateError}(innerErr(ArgGateError(GATE_NoMatch, tok, "")))
end

function complete(p::ArgGate, st::GateState)
    return st
end
