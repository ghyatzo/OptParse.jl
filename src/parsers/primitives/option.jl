const OptionState{X} = Result{X, String}

# options with values: -o 123 / --option valu
struct ArgOption{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    _dummy::P
    #
    valparser::ValueParser{T}
    names::Vector{String}
    description::String


    ArgOption(names::Tuple{Vararg{String}}, valparser::ValueParser{T}; description = "") where {T} =
        new{T, OptionState{T}, 10, Nothing}(Err("Missing Option(s) $(names)."), nothing, valparser, [names...], description)
end


function parse(p::ArgOption{T, OptionState{T}}, ctx::Context{OptionState{T}})::ParseResult{OptionState{T}, String} where {T}

    if ctx.optionsTerminated
        return ParseErr(0, "No more options to be parsed.")
    elseif length(ctx.buffer) < 1
        return ParseErr(0, "Expected option got end of input.")
    end

    # When the input contains `--` is a signal to stop parsing options
    if (ctx.buffer[1] === "--")
        next = Context(ctx.buffer[2:end], ctx.state, true)
        return ParseOk(("--",), next)
    end

    # when options are of the form `--option value` or `/O value`
    if ctx.buffer[1] in p.names

        # st = @? ctx.state
        if !is_error(ctx.state) && unwrap(ctx.state) isa T
            return ParseErr(1, "$(ctx.buffer[1]) cannot be used multiple times")
        end

        if length(ctx.buffer) < 2 || ctx.buffer[2] == "--"
            return ParseErr(1, "Option $(ctx.buffer[1]) requires a value, but got no value.")
        end

        result = p.valparser(ctx.buffer[2])::Result{T, String}

        return ParseOk(
            ctx.buffer[1:2],

            Context(
                ctx.buffer[3:end],
                result,
                ctx.optionsTerminated
            )
        )
    end

    # when options are of the form `--option=value` or `/O:value`
    prefixes = filter(p.names) do name
        startswith(name, "--") || startswith(name, "/")
    end
    map!(prefixes) do name
        startswith(name, "/") ? "$name:" : "$name="
    end
    for prefix in prefixes
        startswith(ctx.buffer[1], prefix) || continue

        if !is_error(ctx.state) && unwrap(ctx.state)
            return ParseErr(1, "$(prefix[1:(end - 1)]) cannot be used multiple times")
        end

        value = ctx.buffer[1][(length(prefix) + 1):end]
        result = p.valparser(value)::Result{T, String}

        return ParseOk(
            ctx.buffer[1:1],

            Context(
                ctx.buffer[2:end],
                result,
                ctx.optionsTerminated
            )
        )

    end

    return ParseErr(
        0, "No Matched option for $(ctx.buffer[1])"
    )
end

function complete(p::ArgOption{T, OptionState{T}}, st::OptionState{T})::Result{T, String} where {T}
    return !is_error(st) ? st : Err("$(p.names): $(unwrap_error(st))")
end
