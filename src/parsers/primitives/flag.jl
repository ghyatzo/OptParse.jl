const FlagState = ParseResult{Bool}

@enum FlagErrCode::UInt8 begin
    FLAG_NoMoreOptions
    FLAG_EndOfInput
    FLAG_Duplicate
    FLAG_NoMatch
    FLAG_Missing
end

argflag_error(code::FlagErrCode; token = "", detail = "", subject="") =
    mkerror(ParsePhase, ERR_ArgFlag, UInt8(code);
        token,
        detail,
        context= isempty(subject) ? ErrorSite[] : ErrorSite[ErrorSite(ParsePhase, ERR_ArgFlag, subject)]
    )

function argflag_render_error(io::IO, code::FlagErrCode, err::ParseError)
    if code == FLAG_NoMoreOptions
        print(io, "No more options can be parsed")
    elseif code == FLAG_EndOfInput
        print(io, "Expected a flag, got end of input")
    elseif code == FLAG_Duplicate
        print(io, "Flag $(err.token) cannot be used multiple times")
    elseif code == FLAG_NoMatch
        print(io, "Unexpected flag: $(err.token)")
    elseif code == FLAG_Missing
        print(io, "Missing required flag(s): $(err.detail)")
    else
        print(io, "unreachable")
    end
end

# single boolean flags: -q --long
struct ArgFlag{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    _dummy::P
    #
    names::Vector{String}
    help::String


    ArgFlag(names::Tuple{Vararg{String}}; help = "") = begin
        for name in names
            if !startswith(name, r"^--?[^-]")
                throw(ArgumentError("Flags and option names must start with `-` or `--`."))
            end
            if startswith(name, r"^-[^-]") && length(name) > 2
                throw(ArgumentError("Short options and flags must only have 1 character."))
            end

        end
        new{Bool, FlagState, 9, Nothing}(typedErr(argflag_error(FLAG_Missing; detail="$(names)")), nothing, [names...], help)
        # new{Bool, FlagState, 9, Nothing}(typedErr("Missing Flag(s) $(names)."), nothing, [names...], help)
    end
end


function parse(p::ArgFlag{Bool, FlagState}, ctx::Context{FlagState})::InnerParseResult{FlagState}

    if ℒ_optterm(ctx)
        return innerErr(ctx, argflag_error(FLAG_NoMoreOptions))
    elseif ctx_hasnone(ctx)
        return innerErr(ctx, argflag_error(FLAG_EndOfInput))
    end

    tok = ctx_peek(ctx)

    #= When the input contains `--` stop parsing options =#
    if (tok === "--")
        nextctx = ctx_with_options_terminated(consume(ctx, 1), true)
        return innerOk(ctx, 1; nextctx)
    end

    if tok in p.names

        if !is_error(ℒ_state(ctx)) && unwrap(ℒ_state(ctx))
            return innerErr(ctx, argflag_error(FLAG_Duplicate; token = tok); consumed = 1)
        end

        nextctx = ctx_with_state(consume(ctx, 1), FlagState(typedOk(true)))
        return innerOk(ctx, 1; nextctx)
    end

    return innerErr(ctx, argflag_error(FLAG_NoMatch; token = tok))
end

function complete(p::ArgFlag, st::FlagState)::ParseResult{Bool}
    return !is_error(st) ? st : typedErr(
        error_with_context(st,
            CompletePhase,
            ERR_ArgFlag,
            p.names[1]
        )
    )
end
