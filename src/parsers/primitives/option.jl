const OptionState{X} = ParseResult{X}

@enum OptionErrCode::UInt8 begin
    OPTION_NoMoreOptions
    OPTION_EndOfInput
    OPTION_Terminator
    OPTION_Duplicate
    OPTION_MissingValue
    OPTION_NoMatch
    OPTION_Missing
    OPTION_InvalidValue
end

argoption_error(code::OptionErrCode; token = "", detail = "", subject="") =
    mkerror(ParsePhase, ERR_ArgOption, UInt8(code);
        token,
        detail,
        context= isempty(subject) ? ErrorSite[] : ErrorSite[ErrorSite(ParsePhase, ERR_ArgOption, subject)]
    )

function argoption_render_error(io::IO, code::OptionErrCode, err::ParseError)
    # pass
end

# options with values: -o 123 / --option valu
struct ArgOption{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    _dummy::P
    #
    valparser::ValueParser{T}
    names::Vector{String}
    help::String


    ArgOption(names::Tuple{Vararg{String}}, valparser::ValueParser{T}; help = "") where {T} = begin
        for name in names
            if !startswith(name, r"^--?[^-]")
                throw(ArgumentError("Flags and option names must start with `-` or `--`."))
            end
            if startswith(name, r"^-[^-]") && length(name) > 2
                throw(ArgumentError("Short options and flags must only have 1 character."))
            end
        end

        new{T, OptionState{T}, 10, Nothing}(
            typedErr(argoption_error(OPTION_Missing; detail="$(names)")),
            nothing,
            valparser,
            [names...],
            help
        )
    end
end


function parse(p::ArgOption{T, OptionState{T}}, ctx::Context{OptionState{T}})::InnerParseResult{OptionState{T}} where {T}

    if ℒ_optterm(ctx)
        return innerparseerr(ctx, argoption_error(OPTION_NoMoreOptions))
    elseif ctx_hasnone(ctx)
        return innerparseerr(ctx, argoption_error(OPTION_EndOfInput))
    end

    tok = ctx_peek(ctx)

    # When the input contains `--` is a signal to stop parsing options
    if (tok === "--")
        nextctx = ctx_with_options_terminated(consume(ctx, 1), true)
        return innerparseok(ctx, 1; nextctx)
    end

    # when options are of the form `--option value`
    if tok in p.names

        # st = @? ctx.state
        if !is_error(ℒ_state(ctx)) && unwrap(ℒ_state(ctx)) isa T
            return innerparseerr(ctx, argoption_error(OPTION_Duplicate; token = tok); consumed = 1)
        end

        if ctx_haslessthan(2, ctx) || ctx_peek(ctx, 2) == "--"
            return innerparseerr(ctx, argoption_error(OPTION_MissingValue; token=tok); consumed = 1)
        end

        result = p.valparser(ctx_peek(ctx, 2))::ParseResult{T}

        return innerparseok(ctx, 2; nextctx = ctx_with_state(consume(ctx, 2), result))
    end

    # when options are of the form `--option=value`
    prefixes = filter(p.names) do name
        startswith(name, "--")
    end
    map!(prefixes) do name
        "$name="
    end
    for prefix in prefixes
        startswith(tok, prefix) || continue

        if !is_error(ℒ_state(ctx)) && unwrap(ℒ_state(ctx))

            return innerparseerr(ctx, argoption_error(OPTION_Duplicate; token = prefix[1:(end - 1)]); consumed = 1)
        end

        value = tok[(length(prefix) + 1):end]
        result = p.valparser(value)::ParseResult{T}

        return innerparseok(ctx, 1; nextctx = ctx_with_state(consume(ctx, 1), result))

    end

    return innerparseerr(ctx, argoption_error(OPTION_NoMatch; token=tok))
end

function complete(p::ArgOption{T, OptionState{T}}, st::OptionState{T})::ParseResult{T} where {T}
    # if the state is an error it means that the valueparser returned an error. we then just need to append
    # a new context to the error and resurface
    return !iserror(st) ? st : typedErr(
        error_with_context(st,
            CompletePhase,
            ERR_ArgOption,
            p.names[1]
        )
    )
end
