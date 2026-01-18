const FlagState = Result{Bool, String}

# single boolean flags: -q --long
struct ArgFlag{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    _dummy::P
    #
    names::Vector{String}
    help::String


    ArgFlag(names::Tuple{Vararg{String}}; help = "") =
        new{Bool, FlagState, 9, Nothing}(Err("Missing Flag(s) $(names)."), nothing, [names...], help)
end


function parse(p::ArgFlag{Bool, FlagState}, ctx::Context{FlagState})::ParseResult{FlagState, String}

    if ℒ_optterm(ctx)
        return ParseErr(0, "No more options to be parsed.")
    elseif ctx_hasnone(ctx)
        return ParseErr(0, "Expected a flag, got end of input.")
    end

    tok = ctx_peek(ctx)

    #= When the input contains `--` stop parsing options =#
    if (tok === "--")
        next = ctx_with_options_terminated(consume(ctx, 1), true)
        return ParseOk(tok, next)
    end

    if tok in p.names

        if !is_error(ℒ_state(ctx)) && unwrap(ℒ_state(ctx))
            return ParseErr(1, "$(tok) cannot be used multiple times")
        end

        return ParseOk(
            tok,
            ctx_with_state(consume(ctx, 1), FlagState(Ok(true)))
        )
    end

    #= When the input contains bundled options: -abc =#
    short_options = filter(p.names) do name
        match(r"^-[^-]$", name) !== nothing
    end

    for short_opt in short_options
        startswith(tok, short_opt) || continue

        if !is_error(ℒ_state(ctx)) && unwrap(ℒ_state(ctx))
            return ParseErr(1, "Flag $(short_opt) cannot be used multiple times")
        end

        #= we consume only the first option in case they are bundled. =#
        single_opt = tok[1:2] #= the "-a" in "-abc" =#
        rem_opts = tok[3:end] #= the "bc" in "-abc" =#

        newbuff = ["-$(rem_opts )", ℒ_buffer(ctx)[2:end]...]

        return ParseOk(
            single_opt,
            ctx_with_state(ctx_with_buffer(ctx, newbuff), Result{Bool, String}(Ok(true)))
        )
    end

    return ParseErr(
        0, "No Matched Flag for $(tok)"
    )
end

function complete(p::ArgFlag, st::FlagState)::Result{Bool, String}
    return !is_error(st) ? st : Err("$(p.names): $(unwrap_error(st))")
end
