const FlagState = Result{Bool, String}

# single boolean flags: -q --long
struct ArgFlag{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    _dummy::P
    #
    names::Vector{String}
    description::String


    ArgFlag(names::Tuple{Vararg{String}}; description = "") =
        new{Bool, FlagState, 9, Nothing}(Err("Missing Flag(s) $(names)."), nothing, [names...], description)
end


function parse(p::ArgFlag{Bool, FlagState}, ctx::Context{FlagState})::ParseResult{FlagState, String}

    if ctx.optionsTerminated
        return ParseErr(0, "No more options to be parsed.")
    elseif length(ctx.buffer) < 1
        return ParseErr(0, "Expected a flag, got end of input.")
    end

    #= When the input contains `--` stop parsing options =#
    if (ctx.buffer[1] === "--")
        next = Context(ctx.buffer[2:end], ctx.state, true)
        return ParseOk(("--",), next)
    end

    if ctx.buffer[1] in p.names

        if !is_error(ctx.state) && unwrap(ctx.state)
            return ParseErr(1, "$(ctx.buffer[1]) cannot be used multiple times")
        end

        return ParseOk(
            ctx.buffer[1:1],

            Context(
                ctx.buffer[2:end],
                FlagState(Ok(true)),
                ctx.optionsTerminated
            )
        )
    end

    #= When the input contains bundled options: -abc =#
    short_options = filter(p.names) do name
        match(r"^-[^-]$", name) !== nothing
    end

    for short_opt in short_options
        startswith(ctx.buffer[1], short_opt) || continue

        if !is_error(ctx.state) && unwrap(ctx.state)
            return ParseErr(1, "Flag $(short_opt) cannot be used multiple times")
        end

        return ParseOk(
            ctx.buffer[1][1:2],

            Context(
                ["-$(ctx.buffer[1][3:end])", ctx.buffer[2:end]...],
                Result{Bool, String}(Ok(true)),
                ctx.optionsTerminated
            )
        )
    end

    return ParseErr(
        0, "No Matched Flag for $(ctx.buffer[1])"
    )
end

function complete(p::ArgFlag, st::FlagState)::Result{Bool, String}
    return !is_error(st) ? st : Err("$(p.names): $(unwrap_error(st))")
end
