const ArgumentState{X} = Option{ParseResult{X}}

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


struct ArgArgument{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    valparser::P

    ArgArgument(valparser::AbstractValueParser{T}) where {T} =
        new{T, ArgumentState{T}, 5, typeof(valparser)}(none(ParseResult{T}), valparser)
end

usage(p::ArgArgument) = UsageArgument(trymetavar(p.valparser))
helpentries(p::ArgArgument, rt::OverlayContext) = [HelpEntry(usage(p), helpinfo(rt))]
focused_helpdoc(
    p::ArgArgument{T, ArgumentState{S}},
    ctx::Context{ArgumentState{S}},
    prefix::Vector{String},
    rt::OverlayContext
) where {T, S} = HelpDoc(prefix, usage(p), helpinfo(rt), HelpEntry[])

function parse(p::ArgArgument{T, ArgumentState{S}}, ctx::Context{ArgumentState{S}})::InnerParseResult{ArgumentState{S}} where {T, S}
    optpattern = r"^--?[a-z0-9-]+$"i

    if ctx_hasnone(ctx)
        return innerErr(
            ctx, ArgArgumentError(
                ARGUMENT_EndOfInput, "",
                trymetavar(p.valparser)
            )
        )
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
            return innerErr(
                ctx, ArgArgumentError(
                    ARGUMENT_GotOption,
                    ctx_peek(ctx, 1 + i),
                    trymetavar(p.valparser)
                );
                consumed = i
            )
        end
    end

    if ctx_haslessthan(1 + i, ctx)
        #=Check again, in case we only had a "--" in the buffer.=#
        return innerErr(
            ctx, ArgArgumentError(
                ARGUMENT_EndOfInput, "",
                trymetavar(p.valparser)
            );
            consumed = i
        )
    end

    if !is_error(ctx_state(ctx))
        #=The state is a some, so this parser matched already with something.
        Add one to the consumed since we're technically consuming this duplicate=#
        return innerErr(
            ctx, ArgArgumentError(
                ARGUMENT_Duplicate, "",
                trymetavar(p.valparser)
            );
            consumed = 1 + i
        )
    end

    result = p.valparser(ctx_peek(ctx, 1 + i))::ParseResult{T}

    nextctx = ctx_with_options_terminated(ctx_with_state(consume(ctx, i + 1), some(result)), options_terminated)
    return innerOk(ctx, 1 + i; nextctx)

end

function complete(p::ArgArgument{T, <:ArgumentState}, maybest::TState)::ParseResult{T} where {T, TState <: ArgumentState}

    #=The parser never matched anything.=#
    is_error(maybest) && return typedErr(
        T, ArgArgumentError(ARGUMENT_TooFew, "", trymetavar(p.valparser))
    )

    st = unwrap(maybest)
    #=The parser matched but there was a parsing error.=#
    is_error(st) && return typedErr(unwrap_error(st))

    return st
end
