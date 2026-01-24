const OptionState{X} = Result{X, String}

# options with values: -o 123 / --option valu
struct ArgOption{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    _dummy::P
    #
    valparser::ValueParser{T}
    names::Vector{String}
    help::String


    ArgOption(names::Tuple{Vararg{String}}, valparser::ValueParser{T}; help = "") where {T} = begin
        for name in names
            if !startswith(name, r"^--?[^-]")
                throw(ArgumentError("Flags and option names must start with `-` or `--`."))
            end
            if startswith(name, r"^-[^-]") && length(name) > 2
                throw(ArgumentError("Short options and flags must only have 1 character."))
            end
        end
        new{T, OptionState{T}, 10, Nothing}(Err("Missing Option(s): $(names)."), nothing, valparser, [names...], help)
    end
end


function parse(p::ArgOption{T, OptionState{T}}, ctx::Context{OptionState{T}})::ParseResult{OptionState{T}, String} where {T}

    if ℒ_optterm(ctx)
        return parseerr(ctx, "No more options to be parsed.")
    elseif ctx_hasnone(ctx)
        return parseerr(ctx, "Expected option got end of input.")
    end

    tok = ctx_peek(ctx)

    # When the input contains `--` is a signal to stop parsing options
    if (tok === "--")
        nextctx = ctx_with_options_terminated(consume(ctx, 1), true)
        return parseok(ctx, 1; nextctx)
    end

    # when options are of the form `--option value`
    if tok in p.names

        # st = @? ctx.state
        if !is_error(ℒ_state(ctx)) && unwrap(ℒ_state(ctx)) isa T
            return parseerr(ctx, "$(tok) cannot be used multiple times"; consumed = 1)
        end

        if ctx_haslessthan(2, ctx) || ctx_peek(ctx, 2) == "--"
            return parseerr(ctx, "Option $(tok) requires a value, but got no value."; consumed = 1)
        end

        result = p.valparser(ctx_peek(ctx, 2))::Result{T, String}

        return parseok(ctx, 2; nextctx = ctx_with_state(consume(ctx, 2), result))
    end

    # when options are of the form `--option=value`
    prefixes = filter(p.names) do name
        startswith(name, "--")
    end
    map!(prefixes) do name
        "$name="
    end
    for prefix in prefixes
        startswith(tok, prefix) || continue

        if !is_error(ℒ_state(ctx)) && unwrap(ℒ_state(ctx))
            return parseerr(ctx, "$(prefix[1:(end - 1)]) cannot be used multiple times"; consumed = 1)
        end

        value = tok[(length(prefix) + 1):end]
        result = p.valparser(value)::Result{T, String}

        return parseok(ctx, 1; nextctx = ctx_with_state(consume(ctx, 1), result))

    end

    return parseerr(ctx, "No Matched option for $(tok)")
end

function complete(p::ArgOption{T, OptionState{T}}, st::OptionState{T})::Result{T, String} where {T}
    return !is_error(st) ? st : Err("$(p.names[1]): $(unwrap_error(st))") # string of vector calls show which is not trimmable.
end
