const FlagState = Result{Bool, String}

# single boolean flags: -q --long
struct ArgFlag{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    _dummy::P
    #
    names::Vector{String}
    help::String


    ArgFlag(names::Tuple{Vararg{String}}; help = "") = begin
        for name in names
            if !startswith(name, r"^--?[^-]")
                throw(ArgumentError("Flags and option names must start with `-` or `--`."))
            end
            if startswith(name, r"^-[^-]") && length(name) > 2
                throw(ArgumentError("Short options and flags must only have 1 character."))
            end

        end
        new{Bool, FlagState, 9, Nothing}(Err("Missing Flag(s) $(names)."), nothing, [names...], help)
    end
end


function parse(p::ArgFlag{Bool, FlagState}, ctx::Context{FlagState})::ParseResult{FlagState, String}

    if ℒ_optterm(ctx)
        return ParseErr("No more options to be parsed.", ctx)
    elseif ctx_hasnone(ctx)
        return ParseErr("Expected a flag, got end of input.", ctx)
    end

    tok = ctx_peek(ctx)

    #= When the input contains `--` stop parsing options =#
    if (tok === "--")
        nextctx = ctx_with_options_terminated(consume(ctx, 1), true)
        return ParseOk(ctx, 1; nextctx)
    end

    if tok in p.names

        if !is_error(ℒ_state(ctx)) && unwrap(ℒ_state(ctx))
            return ParseErr("$(tok) cannot be used multiple times", ctx; consumed = 1)
        end

        return ParseOk(ctx, 1;
            nextctx = ctx_with_state(consume(ctx, 1), FlagState(Ok(true)))
        )
    end

    #= This is no longer needed. We expand all bundled options beforehand =#
    # #= When the input contains bundled options: -abc =#
    # short_options = filter(p.names) do name
    #     match(r"^-[^-]$", name) !== nothing
    # end

    # for short_opt in short_options
    #     startswith(tok, short_opt) || continue

    #     if !is_error(ℒ_state(ctx)) && unwrap(ℒ_state(ctx))
    #         return ParseErr("Flag $(short_opt) cannot be used multiple times", ctx; consumed = 1)
    #     end

    #     #= we consume only the first option in case they are bundled. =#
    #     single_opt = tok[1:2] #= the "-a" in "-abc" =#
    #     rem_opts = tok[3:end] #= the "bc" in "-abc" =#

    #     #= we create a new buffer:
    #         - we turn the "-abc" entry at position p into "-bc"
    #         - then we add the "-a" entry at position p (which is now before "-bc")
    #         - we can now consume the "-a" value
    #     =#
    #     nextctx = set(ctx, IndexLens(ℒ_pos(ctx)) ∘ ℒ_buffer, "-$rem_opts")
    #     nextctx = insert(nextctx, IndexLens(ℒ_pos(ctx)) ∘ ℒ_buffer, single_opt)
    #     nextctx = ctx_with_state(nextctx, Result{Bool, String}(Ok(true)))

    #     #= we need to consume afterwards since otherwise we consume twice =#
    #     return ParseOk(nextctx, 1; nextctx=consume(nextctx,1))

    # end

    return ParseErr("No Matched Flag for $(tok)", ctx)
end

function complete(p::ArgFlag, st::FlagState)::Result{Bool, String}
    return !is_error(st) ? st : Err("$(p.names[1]): $(unwrap_error(st))")
end
