const OptionState{X} = Result{X, String}

# options with values: -o 123 / --option valu
struct ArgOption{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    _dummy::P
    #
    valparser::ValueParser{T}
    names::Vector{String}
    help::String


    ArgOption(names::Tuple{Vararg{String}}, valparser::ValueParser{T}; help = "") where {T} =
        new{T, OptionState{T}, 10, Nothing}(Err("Missing Option(s) $(names)."), nothing, valparser, [names...], help)
end


function parse(p::ArgOption{T, OptionState{T}}, ctx::Context{OptionState{T}})::ParseResult{OptionState{T}, String} where {T}

    if ℒ_optterm(ctx)
        return ParseErr(0, "No more options to be parsed.")
    elseif ctx_hasnone(ctx)
        return ParseErr(0, "Expected option got end of input.")
    end

    tok = ctx_peek(ctx)

    # When the input contains `--` is a signal to stop parsing options
    if (tok === "--")
        next = ctx_with_options_terminated(consume(ctx, 1), true)
        return ParseOk(tok, next)
    end

    # when options are of the form `--option value` or `/O value`
    if tok in p.names

        # st = @? ctx.state
        if !is_error(ℒ_state(ctx)) && unwrap(ℒ_state(ctx)) isa T
            return ParseErr(1, "$(tok) cannot be used multiple times")
        end

        if ctx_haslessthan(2, ctx) || ctx_peek(ctx, 2) == "--"
            return ParseErr(1, "Option $(tok) requires a value, but got no value.")
        end

        result = p.valparser(ctx_peek(ctx, 2))::Result{T, String}

        return ParseOk(
            ctx_peekn(ctx, 2),
            ctx_with_state(consume(ctx, 2), result)
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
        startswith(tok, prefix) || continue

        if !is_error(ℒ_state(ctx)) && unwrap(ℒ_state(ctx))
            return ParseErr(1, "$(prefix[1:(end - 1)]) cannot be used multiple times")
        end

        value = tok[(length(prefix) + 1):end]
        result = p.valparser(value)::Result{T, String}

        return ParseOk(
            tok,
            ctx_with_state(consume(ctx, 1), result)
        )

    end

    return ParseErr(
        0, "No Matched option for $(tok)"
    )
end

function complete(p::ArgOption{T, OptionState{T}}, st::OptionState{T})::Result{T, String} where {T}
    return !is_error(st) ? st : Err("$(p.names): $(unwrap_error(st))")
end
