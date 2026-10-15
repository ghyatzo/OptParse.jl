@sum_type ArgumentState{X, E} :hidden begin
    NotMatched
    Matched{X}(value::X)
    Invalid{E}(error::E)
end

@enum ArgumentErrCode::UInt8 begin
    ARGUMENT_EndOfInput
    ARGUMENT_GotOption
    ARGUMENT_Duplicate
    ARGUMENT_TooFew
end

struct ArgArgumentError <: AbstractParseError
    code::ArgumentErrCode
    token::String
    detail::String
end

function render_error(io::IO, err::ArgArgumentError)
    return if err.code == ARGUMENT_EndOfInput
        print(io, "Expected $(err.detail), got end of input")
    elseif err.code == ARGUMENT_GotOption
        if isempty(err.token)
            print(io, "Expected $(err.detail), got an option or flag")
        else
            print(io, "Expected $(err.detail), got option or flag $(err.token)")
        end
    elseif err.code == ARGUMENT_Duplicate
        print(io, "Argument $(err.detail) cannot be used multiple times")
    elseif err.code == ARGUMENT_TooFew
        print(io, "Expected $(err.detail), but too few arguments")
    else
        print(io, "unreachable")
    end
end


struct ArgArgument{T, E, S, P, R} <: AbstractParser{T, E, S, P, R}
    initialState::S
    valparser::P

    function ArgArgument(valparser::AbstractValueParser{T, IE}) where {T, IE}
        UE = Union{ArgArgumentError, IE}
        return new{
            T, UE, ArgumentState{T, IE}, typeof(valparser),5
        }(ArgumentState{T, IE}'.NotMatched, valparser)
    end
end

usage(p::ArgArgument) = UsageArgument(
    metavar(p.valparser);
    annotations = usage_annotations(p.valparser)
)

helpentries(p::ArgArgument, rt::OverlayContext) = [HelpEntry(usage(p), helpinfo(rt))]

focused_helpdoc(
    p::ArgArgument{<:Any, <:Any, ArgumentState{S, E}},
    ::Context{ArgumentState{S, E}},
    prefix::Vector{String},
    rt::OverlayContext
) where {S, E} = HelpDoc(prefix, usage(p), helpinfo(rt), HelpEntry[])

function parse(
    p::ArgArgument{T, E, ArgumentState{S, IE}}, ctx::Context{ArgumentState{S, IE}}
) where {T, E, S, IE <: E}
    optpattern = r"^--?[a-z0-9-]+$"i

    if hasnone(ctx)
        return InnerResult{ArgumentState{S, IE}, E}(innerErr(
            ArgArgumentError(ARGUMENT_EndOfInput, "", metavar(p.valparser)),
            consumed = 0
        ))
    end

    matched = @cases state(ctx) begin
        NotMatched => false
        Matched(_) => true
        Invalid(_) => true
    end

    if matched
        return InnerResult{ArgumentState{S, IE}, E}(innerErr(
            ArgArgumentError(ARGUMENT_Duplicate, "", metavar(p.valparser));
            consumed = 0
        ))
    end

    i = 0

    tok = peek(ctx)
    optterm = options_terminated(ctx)
    if !optterm
        #=Options aren't "officially" terminated yet. Need to be careful.=#
        if tok == "--"
            #=If we encounter "--" consume it and update the context=#
            optterm = true
            #=we have to consume an extra token=#
            i += 1
        elseif !isnothing(match(optpattern, peek(ctx, 1 + i)))
            #=Otherwise, check that we are not matching an option.=#
            return InnerResult{ArgumentState{S, IE}, E}(innerErr(
                ArgArgumentError(ARGUMENT_GotOption, peek(ctx, 1 + i), metavar(p.valparser));
                consumed = i
            ))
        end
    end

    if haslessthan(1 + i, ctx)
        #=Check again, in case we only had a "--" in the buffer.=#
        return InnerResult{ArgumentState{S, IE}, E}(innerErr(
            ArgArgumentError(ARGUMENT_EndOfInput, "", metavar(p.valparser));
            consumed = i
        ))
    end

    result = p.valparser(peek(ctx, 1 + i))

    (; Matched, Invalid) = ArgumentState{S, IE}'
    nextstate = is_error(result) ? Invalid(unwrap_error(result)) : Matched(unwrap(result))
    nextctx = with_options_terminated(ctx, optterm)
    nextctx = with_state(nextctx, nextstate)

    return InnerResult{ArgumentState{S, IE}, E}(innerOk(nextctx, 1 + i))

end

function complete(
    p::ArgArgument{T, E, S}, st::S
) where {T, E, IE <: E, S <: ArgumentState{T, IE}}
    @cases st begin
        NotMatched => return Result{T, E}'.Err(ArgArgumentError(ARGUMENT_TooFew, "", metavar(p.valparser)))
        Matched(value) => return Result{T, E}'.Ok(value)
        Invalid(error) => return Result{T, E}'.Err(error)
    end
end
