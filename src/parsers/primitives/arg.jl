const ArgumentState{X, E} = Option{ParseResult{X, E}}

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
        return new{T, UE, ArgumentState{T, IE}, typeof(valparser), 5}(none(ParseResult{T, IE}), valparser)
    end
end

usage(p::ArgArgument) = UsageArgument(metavar(p.valparser))
helpentries(p::ArgArgument, rt::OverlayContext) = [HelpEntry(usage(p), helpinfo(rt))]
focused_helpdoc(
    p::ArgArgument{<:Any, <:Any, ArgumentState{S, E}},
    ::Context{ArgumentState{S, E}},
    prefix::Vector{String},
    rt::OverlayContext
) where {S, E} = HelpDoc(prefix, usage(p), helpinfo(rt), HelpEntry[])

function parse(p::ArgArgument{T, E, ArgumentState{S, IE}}, ctx::Context{ArgumentState{S, IE}}) where {T, E, S, IE <: E}
    optpattern = r"^--?[a-z0-9-]+$"i

    if ctx_hasnone(ctx)
        return InnerParseResult{ArgumentState{S, IE}, E}(innerErr(
            ArgArgumentError(ARGUMENT_EndOfInput, "", metavar(p.valparser)),
            consumed = 0
        ))
    end

    i = 0

    tok = ctx_peek(ctx)
    options_terminated = ctx_optterm(ctx)
    if !options_terminated
        #=Options aren't "officially" terminated yet. Need to be careful.=#
        if tok == "--"
            #=If we encounter "--" consume it and update the context=#
            options_terminated = true
            #=we have to consume an extra token=#
            i += 1
        elseif !isnothing(match(optpattern, ctx_peek(ctx, 1 + i)))
            #=Otherwise, check that we are not matching an option.=#
            return InnerParseResult{ArgumentState{S, IE}, E}(innerErr(
                ArgArgumentError(ARGUMENT_GotOption, ctx_peek(ctx, 1 + i), metavar(p.valparser));
                consumed = i
            ))
        end
    end

    if ctx_haslessthan(1 + i, ctx)
        #=Check again, in case we only had a "--" in the buffer.=#
        return InnerParseResult{ArgumentState{S, IE}, E}(innerErr(
            ArgArgumentError(ARGUMENT_EndOfInput, "", metavar(p.valparser));
            consumed = i
        ))
    end

    if !is_error(ctx_state(ctx))
        #=The state is a some, so this parser matched already with something.
        Add one to the consumed since we're technically consuming this duplicate=#
        return InnerParseResult{ArgumentState{S, IE}, E}(innerErr(
            ArgArgumentError(ARGUMENT_Duplicate, "", metavar(p.valparser));
            consumed = 1 + i
        ))
    end

    result = p.valparser(ctx_peek(ctx, 1 + i))

    nextctx = ctx_with_options_terminated(ctx, options_terminated)
    nextctx = ctx_with_state(nextctx, some(result))

    return InnerParseResult{ArgumentState{S, IE}, E}(
        innerOk(nextctx, 1+i)
    )

end

function complete(p::ArgArgument{T, E, S}, maybest::S) where {T, E, IE <: E, S <: ArgumentState{T, IE}}

    #=The parser never matched anything.=#
    is_error(maybest) && return ParseResult{T, E}(
        typedErr(E, ArgArgumentError(ARGUMENT_TooFew, "", metavar(p.valparser)))
    )

    st = unwrap(maybest)
    #=The parser matched but there was a parsing error.=#
    is_error(st) && return ParseResult{T, E}(
        typedErr(E, unwrap_error(st))
    )

    return ParseResult{T, E}(typedOk(T, unwrap(st)))
end
