const OptionState{X, E} = ParseResult{X, E}

@enum OptionErrCode::UInt8 begin
    OPTION_NoMoreOptions
    OPTION_EndOfInput
    OPTION_Duplicate
    OPTION_MissingValue
    OPTION_NoMatch
    OPTION_Missing
end

struct ArgOptionError <: AbstractParseError
    code::OptionErrCode
    token::String
    detail::String
end

function render_error(io::IO, err::ArgOptionError)
    return if err.code == OPTION_NoMoreOptions
        print(io, "No more options can be parsed")
    elseif err.code == OPTION_EndOfInput
        print(io, "Expected an option, got end of input")
    elseif err.code == OPTION_Duplicate
        print(io, "Option $(err.token) cannot be used multiple times")
    elseif err.code == OPTION_MissingValue
        print(io, "Option $(err.token) requires a value")
    elseif err.code == OPTION_NoMatch
        print(io, "Unexpected option: $(err.token)")
    elseif err.code == OPTION_Missing
        print(io, "Missing required option(s): $(err.detail)")
    else
        print(io, "unreachable")
    end
end

# options with values: -o 123 / --option valu
struct ArgOption{T, E, S, P, R} <: AbstractParser{T, E, S, P, R}
    initialState::S
    valparser::P
    #
    names::Vector{String}


    ArgOption(names::Tuple{Vararg{String}}, valparser::AbstractValueParser{T, IE}) where {T, IE} = begin
        for name in names
            if !startswith(name, r"^--?[^-]")
                throw(ArgumentError("Flags and option names must start with `-` or `--`."))
            end
            if startswith(name, r"^-[^-]") && length(name) > 2
                throw(ArgumentError("Short options and flags must only have 1 character."))
            end
        end

        UE = Union{ArgOptionError, IE}
        new{T, UE, OptionState{T, UE}, typeof(valparser), 10}(
            ParseResult{T, UE}(Err(ArgOptionError(OPTION_Missing, "", "$(names)"))),
            valparser,
            [names...]
        )
    end
end

usage(p::ArgOption) = UsageOption(p.names, metavar(p.valparser))

helpentries(p::ArgOption, rt::OverlayContext) = [HelpEntry(usage(p), helpinfo(rt))]

focused_helpdoc(
    p::ArgOption{<:Any, <:Any, <:OptionState},
    ::Context{<:OptionState},
    prefix::Vector{String},
    rt::OverlayContext
) = HelpDoc(prefix, usage(p), helpinfo(rt), HelpEntry[])


function parse(p::ArgOption{T, E, S}, ctx::Context{S}) where {T, E, IE <: E, S <: OptionState{T, IE}}

    if ctx_optterm(ctx)
        return InnerParseResult{S, E}(innerErr(ArgOptionError(OPTION_NoMoreOptions, "", "")))
    elseif ctx_hasnone(ctx)
        return InnerParseResult{S, E}(innerErr(ArgOptionError(OPTION_EndOfInput, "", "")))
    end

    tok = ctx_peek(ctx)

    # When the input contains `--` is a signal to stop parsing options
    if (tok === "--")
        nextctx = ctx_with_options_terminated(ctx, true)
        return InnerParseResult{S, E}(innerOk(nextctx, 1; counts_as_match = false))
    end

    # when options are of the form `--option value`
    if tok in p.names

        # st = @? ctx.state
        if !is_error(ctx_state(ctx)) && unwrap(ctx_state(ctx)) isa T
            return InnerParseResult{S, E}(innerErr(ArgOptionError(OPTION_Duplicate, tok, ""); consumed = 1))
        end

        if ctx_haslessthan(2, ctx) || ctx_peek(ctx, 2) == "--"
            return InnerParseResult{S, E}(innerErr(ArgOptionError(OPTION_MissingValue, tok, ""); consumed = 1))
        end

        result = p.valparser(ctx_peek(ctx, 2))

        nextctx = widen_restate(S, ctx, result)
        return InnerParseResult{S, E}(innerOk(nextctx, 2))
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

        if !is_error(ctx_state(ctx))

            return InnerParseResult{S, E}(innerErr(ArgOptionError(OPTION_Duplicate, prefix[1:(end - 1)], ""); consumed = 1))
        end

        value = tok[(length(prefix) + 1):end]
        result = p.valparser(value)

        nextctx = widen_restate(S, ctx, result)
        return InnerParseResult{S, E}(innerOk(nextctx, 1))

    end

    return InnerParseResult{S, E}(innerErr(ArgOptionError(OPTION_NoMatch, tok, "")))
end

function complete(p::ArgOption{T, E, S}, st::S) where {T, E, IE <: E, S <: OptionState{T, IE}}
    return !is_error(st) ? ParseResult{T, E}(typedOk(T, unwrap(st))) : ParseResult{T, E}(typedErr(E, unwrap_error(st)))
end
