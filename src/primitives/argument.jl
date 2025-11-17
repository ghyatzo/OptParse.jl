struct ArgArgument{T, S, p, P}
    initialState::S
    _dummy::P
    #
    valparser::ValueParser{T}
    description::String



    ArgArgument(valparser::ValueParser{T}; description = "") where {T} =
        new{T, Option{Result{T, String}}, 5, Nothing}(none(Result{T, String}), nothing, valparser, description)
end

function parse(p::ArgArgument{T, S}, ctx::Context)::ParseResult{S, String} where {T, S}
    optpattern = r"^--?[a-z0-9-]+$"i

    if length(ctx.buffer) < 1
        return ParseErr(0, "Expected argument but got end of input.")
    end

    i = 0
    options_terminated = ctx.optionsTerminated
    if !options_terminated
        if ctx.buffer[1] == "--"
            options_terminated = true
            i += 1
        elseif !isnothing(match(optpattern, ctx.buffer[1+i]))
            return ParseErr(i, "Expected an argument, but got an option/flag.")
        end
    end

    if length(ctx.buffer) < 1 + i
        return ParseErr(i, "Expected argument but got end of input")
    end

    if base(ctx.state) !== nothing
        return ParseErr(i, "The argument `$(metavar(p.valparser))` cannot be used multiple times.")
    end

    @info "buffers" i ctx.buffer[i+1] ctx.buffer[1:i+1] ctx.buffer[i+2:end]
    result = p.valparser(ctx.buffer[1+i])

    return ParseOk(
        ctx.buffer[1:i+1],
        Context(
            ctx.buffer[i+2:end],
            some(result),
            options_terminated
        )
    )
end

function complete(p::ArgArgument{T, S}, maybest::S)::Result{T, String} where {T, S}
    somest = base(maybest)
    if isnothing(somest)
        return Err("Expected a `$(metavar(p.valparser))`, but too few arguments.")
    end
    st = something(somest)
    if !is_error(st)
        return st
    end

    error = unwrap_error(st)
    return Err("`$(metavar(p.valparser))`: $error.")
end
