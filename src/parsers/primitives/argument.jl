const ArgumentState{X} = Option{Result{X, String}}

struct ArgArgument{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    _dummy::P
    #
    valparser::ValueParser{T}
    description::String


    ArgArgument(valparser::ValueParser{T}; description = "") where {T} =
        new{T, ArgumentState{T}, 5, Nothing}(none(Result{T, String}), nothing, valparser, description)
end

function parse(p::ArgArgument{T, ArgumentState{S}}, ctx::Context{ArgumentState{S}})::ParseResult{ArgumentState{S}, String} where {T, S}
    optpattern = r"^--?[a-z0-9-]+$"i

    if length(ctx.buffer) < 1
        return ParseErr(0, "Expected an argument, but got end of input.")
    end

    i = 0
    options_terminated = ctx.optionsTerminated
    if !options_terminated
        #=Options aren't "officially" terminated yet. Need to be careful.=#
        if ctx.buffer[1] == "--"
            #=If we encounter "--" consume it and update the context=#
            options_terminated = true
            i += 1
        elseif !isnothing(match(optpattern, ctx.buffer[1 + i]))
            #=Otherwise, check that we are not matching an option.=#
            return ParseErr(i, "Expected an argument, but got an option/flag.")
        end
    end

    if length(ctx.buffer) < 1 + i
        #=Check again, in case we only had a "--" in the buffer.=#
        return ParseErr(i, "Expected an argument, but got end of input.")
    end

    if !is_error(ctx.state)
        #=The state is a some, so this parser matched already with something.
        Add one to the consumed since we're technically consuming this duplicate=#
        return ParseErr(1+i, "The argument `$(metavar(p.valparser))` cannot be used multiple times.")
    end

    result = p.valparser(ctx.buffer[1 + i])::Result{T, String}

    return ParseOk(
        ctx.buffer[1:(i + 1)],
        Context(
            ctx.buffer[(i + 2):end],
            some(result),
            options_terminated
        )
    )
end

function complete(p::ArgArgument{T, <:ArgumentState}, maybest::TState)::Result{T, String} where {T, TState <: ArgumentState}

    #=The parser never matched anything.=#
    is_error(maybest) && return Err("Expected a `$(metavar(p.valparser))`, but too few arguments.")

    st = unwrap(maybest)
    #=The parser matched but there was a parsing error.=#
    is_error(st) && return Err("`$(metavar(p.valparser))`: $(unwrap_error(st)).")

    return st
end

