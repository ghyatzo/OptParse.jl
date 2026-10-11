@enum ToggleErrCode::UInt8 begin
    TOGGLE_Missing
    TOGGLE_Duplicate
    TOGGLE_Conflict
    TOGGLE_NoMatch
    TOGGLE_NoMoreOptions
    TOGGLE_EndOfInput
end

struct ArgToggleError <: AbstractParseError
    code::ToggleErrCode
    token::String
    detail::String
end

function render_error(io::IO, err::ArgToggleError)
    return if err.code == TOGGLE_Missing
        print(io, "Missing required flag(s): $(err.detail)")
    elseif err.code == TOGGLE_Duplicate
        print(io, "Flag $(err.token) cannot be used multiple times")
    elseif err.code == TOGGLE_Conflict
        print(io, "$(err.token) and $(err.detail) can't be used together")
    elseif err.code == TOGGLE_NoMatch
        print(io, "Unexpected flag: $(err.token)")
    elseif err.code == TOGGLE_NoMoreOptions
        print(io, "No more options can be parsed")
    elseif err.code == TOGGLE_EndOfInput
        print(io, "Expected a flag, got end of input")
    else
        print(io, "unreachable")
    end
end

@sum_type ToggleState :hidden begin
    NotMatched
    Matched(value::Bool)
end

# tri-valued boolean flags: --tags / --no-tags -> nothing / true / false
struct ArgToggle{T, E, S, P, R} <: AbstractParser{T, E, S, P, R}
    initialState::S
    _dummy::P
    #
    positive::String
    negative::String

    ArgToggle(positive::String) = begin
        if !startswith(positive, r"^--[^-]")
            throw(ArgumentError("Toggle names must be long options starting with `--`."))
        end
        if startswith(positive, "--no-")
            throw(ArgumentError("The positive spelling must not start with `--no-`."))
        end

        new{Bool, ArgToggleError, ToggleState, Nothing, 9}(
            ToggleState'.NotMatched,
            nothing,
            positive,
            "--no-" * chop(positive; head = 2, tail = 0)
        )
    end
end

usage(p::ArgToggle) = UsageFlag(String["--[no-]" * chop(p.positive; head = 2, tail = 0)])
helpentries(p::ArgToggle, rt::OverlayContext) = [HelpEntry(usage(p), helpinfo(rt))]
focused_helpdoc(
    p::ArgToggle,
    ::Context{ToggleState},
    prefix::Vector{String},
    rt::OverlayContext
) = HelpDoc(prefix, usage(p), helpinfo(rt), HelpEntry[])

function parse(p::ArgToggle{Bool, ArgToggleError, S}, ctx::Context{S}) where {S <: ToggleState}

    if options_terminated(ctx)
        return InnerResult{S, ArgToggleError}(innerErr(ArgToggleError(TOGGLE_NoMoreOptions, "", "")))
    elseif hasnone(ctx)
        return InnerResult{S, ArgToggleError}(innerErr(ArgToggleError(TOGGLE_EndOfInput, "", "")))
    end

    tok = peek(ctx)

    #= When the input contains `--` stop parsing options =#
    if (tok === "--")
        nextctx = with_options_terminated(ctx, true)
        return InnerResult{S, ArgToggleError}(innerOk(nextctx, 1; counts_as_match = false))
    end

    value = if tok == p.positive
        true
    elseif tok == p.negative
        false
    else
        return InnerResult{S, ArgToggleError}(innerErr(ArgToggleError(TOGGLE_NoMatch, tok, "")))
    end

    @cases state(ctx) begin
        NotMatched => nothing
        Matched(previous) => begin
            code = previous == value ? TOGGLE_Duplicate : TOGGLE_Conflict
            detail = previous == value ? "" : (previous ? p.positive : p.negative)
            return InnerResult{S, ArgToggleError}(
                innerErr(ArgToggleError(code, tok, detail); consumed = 1)
            )
        end
    end

    nextctx = with_state(ctx, ToggleState'.Matched(value))
    return InnerResult{S, ArgToggleError}(innerOk(nextctx, 1))
end

function complete(p::ArgToggle, st::ToggleState)
    @cases st begin
        NotMatched => return Result{Bool, ArgToggleError}'.Err(
            ArgToggleError(TOGGLE_Missing, "", _names_detail([p.positive, p.negative]))
        )
        Matched(value) => return Result{Bool, ArgToggleError}'.Ok(value)
    end
end
