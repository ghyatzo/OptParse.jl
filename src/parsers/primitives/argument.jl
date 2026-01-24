const ArgumentState{X} = Option{Result{X, String}}

struct ArgArgument{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    _dummy::P
    #
    valparser::ValueParser{T}
    help::String


    ArgArgument(valparser::ValueParser{T}; help = "") where {T} =
        new{T, ArgumentState{T}, 5, Nothing}(none(Result{T, String}), nothing, valparser, help)
end

function parse(p::ArgArgument{T, ArgumentState{S}}, ctx::Context{ArgumentState{S}})::ParseResult{ArgumentState{S}, String} where {T, S}
    optpattern = r"^--?[a-z0-9-]+$"i

    if ctx_hasnone(ctx)
        return ParseErr("Expected an argument, but got end of input.", ctx)
    end

    i = 0

    tok = ctx_peek(ctx)
    options_terminated = ℒ_optterm(ctx)
    if !options_terminated
        #=Options aren't "officially" terminated yet. Need to be careful.=#
        if tok == "--"
            #=If we encounter "--" consume it and update the context=#
            options_terminated = true
            #=we have to consume an extra token=#
            i += 1
        elseif !isnothing(match(optpattern, ctx_peek(ctx, 1 + i)))
            #=Otherwise, check that we are not matching an option.=#
            return ParseErr("Expected an argument, but got an option/flag.", ctx; consumed = i)
        end
    end

    if ctx_haslessthan(1+i, ctx)
        #=Check again, in case we only had a "--" in the buffer.=#
        return ParseErr("Expected an argument, but got end of input.", ctx; consumed = i)
    end

    if !is_error(ℒ_state(ctx))
        #=The state is a some, so this parser matched already with something.
        Add one to the consumed since we're technically consuming this duplicate=#
        return ParseErr("The argument `$(metavar(p.valparser))` cannot be used multiple times.", ctx; consumed = 1+i)
    end

    result = p.valparser(ctx_peek(ctx, 1 + i))::Result{T, String}

    nextctx = ctx_with_options_terminated(ctx_with_state(consume(ctx, i+1), some(result)), options_terminated)
    return ParseOk(ctx, 1+i; nextctx)

end

function complete(p::ArgArgument{T, <:ArgumentState}, maybest::TState)::Result{T, String} where {T, TState <: ArgumentState}

    #=The parser never matched anything.=#
    is_error(maybest) && return Err("Expected a `$(metavar(p.valparser))`, but too few arguments.")

    st = unwrap(maybest)
    #=The parser matched but there was a parsing error.=#
    is_error(st) && return Err("`$(metavar(p.valparser))`: $(unwrap_error(st)).")

    return st
end
