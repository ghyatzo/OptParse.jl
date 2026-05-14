# Static (juliac/trim) path for parsing entrypoints.
# Keeps full type parameters for type-stable compiled code.

"""
    tryoptparse(parser, argv)

Lower-level parsing entrypoint.

Returns a result container containing either the parsed value or a structured parse failure.
Unlike [`optparse`](@ref), this function does not throw on parse failures.
"""
@autospecialize pp function tryoptparse(
        pp::AbstractParser{T, S},
        args::Vector{String}
    )::ParseResult{T} where {T, S}

    canonical_argv, _ = normalize_argv(args)
    ctx = Context{S}(buffer = canonical_argv, state = pp.initialState, usage = usage(pp))

    while true
        mayberesult::InnerParseResult{S} = parse(pp, ctx)

        if is_error(mayberesult)
            return typedErr(T, unwrap_error(mayberesult).error)
        end
        result = unwrap(mayberesult)

        previous_buffer = ctx_remaining(ctx)
        ctx = res_nextctx(result)

        if no_progress(previous_buffer, ctx)
            return typedErr(T, main_error(MAIN_NoProgress; token = ctx_peek(ctx)))
        end

        ctx_length(ctx) > 0 || break
    end

    state = ctx_state(ctx)

    return complete(pp, state)
end

"""
    optparse(parser, argv)

High-level parsing entrypoint.

When `juliac` mode is enabled, renders the error to `stderr` and returns
`nothing` on failure instead of throwing.

If you need stable non-throwing behavior across environments, use
[`tryoptparse`](@ref) instead.
"""
@autospecialize pp function optparse(pp::AbstractParser{T}, args::Vector{String}) where {T}
    mayberes = tryoptparse(pp, args)::ParseResult{T}

    if is_error(mayberes)
        errmsg = sprint(
            showerror, ParseException(
                pp, args, unwrap_error(mayberes)
            )
        )
        print(Core.stderr, "Error: ")
        println(Core.stderr, errmsg)
        return nothing
    end

    return unwrap(mayberes)
end

"""
    runparse(parser, argv; progname, help_command, help_flags, on_empty)

Application-facing parsing entrypoint with built-in help handling.

See the main documentation for full keyword argument descriptions.
"""
@autospecialize parser function runparse(
        parser::AbstractParser, argv::Vector{String};
        progname = "",
        help_command = "help",
        help_flags = ["--help"],
        on_empty = isempty(help_command) ? [] : [help_command]
    )

    if isempty(argv)
        argv = on_empty
    end

    nargv, _ = normalize_argv(argv)
    newargv = String[]
    help_request = false
    for (i, token) in enumerate(nargv)
        if token == "--"
            append!(newargv, nargv[i:end])
            break
        end
        if token in help_flags
            help_request = true
            continue
        end
        push!(newargv, token)
    end

    if help_request
        print_help(Core.stderr, parser, newargv; progname)
        return nothing
    end

    if !isempty(help_command)
        _parser = or(hidden(helpcommand(help_command)), parser)
        res = optparse(_parser, newargv)
        if res isa HelpRequest
            print_help(Core.stderr, parser, res.argv; progname)
            return nothing
        end
        return res
    else
        return optparse(parser, newargv)
    end
end
