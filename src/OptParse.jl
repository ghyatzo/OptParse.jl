module OptParse

# Check whether we are compiling with juliac
using Preferences: @load_preference
const juliac = @load_preference("juliac", false)

using Accessors: @o, IndexLens, PropertyLens, insert, set

using WrappedUnions: @unionsplit, @wrapped,
    #=conflicts with the unwrap from ErrorTypes.jl=#
    unwrap as unwrapunion

using ErrorTypes: @?, Err, ErrorTypes, Ok, Option, Result, base, is_error,
    none, some, unwrap, unwrap_error

using UUIDs: UUID, uuid_version

using StructUtils

export
    @?,
    @constant,
    HelpRequest,
    arg,
    optparse,
    choice,
    combine,
    concat,
    construct,
    command,
    default,
    flag,
    flt,
    flt32,
    flt64,
    switch,
    generate_help,
    help,
    helpcommand,
    hidden,
    i16,
    i32,
    i64,
    i8,
    integer,
    many,
    many1,
    record,
    option,
    optional,
    or,
    path,
    print_help,
    repeated,
    runparse,
    str,
    sequence,
    tryoptparse,
    u16,
    u32,
    u64,
    u8,
    uuid,
    valuetype

public build_help_doc, render_helpdoc


abstract type AbstractParser{T, S, p, P} end

tval(::Type{<:AbstractParser{T}}) where {T} = T
tval(::AbstractParser{T}) where {T} = T

tstate(::Type{<:AbstractParser{T, S}}) where {T, S} = S
tstate(::AbstractParser{T, S}) where {T, S} = S

function priority(::Type{<:AbstractParser{T, S, _p}})::Int where {T, S, _p}
    return _p
end
function priority(::AbstractParser{T, S, _p})::Int where {T, S, _p}
    return _p
end

ptypes(::Type{<:AbstractParser{T, S, _p, P}}) where {T, S, _p, P} = P
ptypes(::AbstractParser{T, S, _p, P}) where {T, S, _p, P} = P

"""
    valuetype(parser_or_type)

Return the final value type produced by a parser.

This is mainly useful when you want to refer to the output type of an anonymous
parser in user code.

For application-facing dispatch, prefer constructing a named type directly with
[`construct`](@ref) and dispatching on that type instead.

# Examples
```jldoctest
julia> using OptParse

julia> greet = command("greet", record((
           cmd = @constant(:greet),
           name = option("-n", str("NAME")),
       )));

julia> const Greet = valuetype(greet);

julia> Greet
@NamedTuple{cmd::Val{:greet}, name::String}
```

A common pattern is to define a stable alias once and dispatch on it later when
you do not want to introduce a dedicated struct type.

# See Also
- [`optparse`](@ref)
- [`tryoptparse`](@ref)
- [`construct`](@ref)
"""
valuetype(::Type{<:AbstractParser{T}}) where {T} = T
valuetype(::AbstractParser{T}) where {T} = T

"""
    HelpRequest

Sentinel value returned by [`helpcommand`](@ref).

`argv` stores the help scope that should be passed to [`generate_help`](@ref).
For example, parsing `["help", "remote", "add"]` with `helpcommand()` yields
`HelpRequest(["remote", "add"])`.

This value is mainly useful together with higher-level runners such as
[`runparse`](@ref), which can interpret it and render the corresponding help
page.
"""
struct HelpRequest
    argv::Vector{String}
end

include("utils.jl")
include("core/usage/usage.jl")
include("core/help/help.jl")
include("core/context.jl")
include("core/errors.jl")
include("core/parseresult.jl")
include("parsers/parser.jl")
include("display/parser_show.jl")


"""
    normalize_argv(argv) -> (expanded, origin)

Expands bundled boolean short flags:
    "-abc" -> "-a", "-b", "-c"

Rules:
- Only expand before `--`
- Do not expand tokens starting with "--"
- After `--`, tokens are untouched

Returns:
- expanded::Vector{String}
- origin::Vector{Int}  (expanded index -> original argv index)
"""
function normalize_argv(argv::Vector{String})
    expanded = String[]
    origin = Int[]
    optterm = false

    for (i, tok) in pairs(argv)
        if tok == "--"
            optterm = true
            push!(expanded, tok); push!(origin, i)
            continue
        end

        if !optterm && startswith(tok, "-") && !startswith(tok, "--") && lastindex(tok) > 2
            # "-abc" => "-a","-b","-c"
            for c in tok[2:end]
                push!(expanded, "-" * string(c))
                push!(origin, i)
            end
        else
            push!(expanded, tok); push!(origin, i)
        end
    end

    return expanded, origin
end


function no_progress(previous_buffer, ctx)
    return ctx_length(ctx) > 0 &&
        ctx_length(ctx) == length(previous_buffer) &&
        ctx_remaining(ctx) == previous_buffer
end


function recover_usage_context(pp::AbstractParser{T, S}, argv::Vector{String})::Context{S} where {T, S}
    canonical_argv, _ = normalize_argv(argv)
    ctx = Context{S}(buffer = canonical_argv, state = pp.initialState, usage = @unionsplit usage(pp))

    while true
        mayberesult::InnerParseResult{S} = @unionsplit parse(pp, ctx)

        if is_error(mayberesult)
            return ctx
        end
        result = unwrap(mayberesult)

        previous_buffer = ctx_remaining(ctx)
        ctx = res_nextctx(result)

        if no_progress(previous_buffer, ctx)
            # Top-level progress guard: a parser must not report success while leaving argv unchanged.
            return ctx
        end

        ctx_length(ctx) > 0 || break
    end

    return ctx
end

"""
    build_help_doc(parser, argv)

Build a focused help document for `argv` from `parser`.

This is a structured, cold-path helper used by OptParse's help and error
rendering machinery. It replays enough parser state to determine the most
relevant help scope, then returns a [`HelpDoc`](@ref) for that scope.

Unlike `generate_help`, this function returns the intermediate help document
rather than rendered text. It is useful if you want to inspect or render the
focused help information yourself.

# Examples
```jldoctest
julia> using OptParse

julia> parser = command("serve", record((
           host = option("--host", str("HOST")),
           verbose = flag("-v", "--verbose"),
       )));

julia> doc = OptParse.build_help_doc(parser, ["serve", "--unknown"]);

julia> doc.prefix
1-element Vector{String}:
 "serve"
```

# See Also
- `generate_help`
- `OptParse.render_helpdoc`
"""
function build_help_doc(parser, argv)
    ctx = recover_usage_context(parser, argv)
    return @unionsplit focused_helpdoc(parser, ctx, String[], root_overlay_context())::HelpDoc
end

"""
    generate_help(parser, argv; progname = "")

Generate a rendered help page for `argv` from `parser`.

This is a high-level convenience wrapper around `build_help_doc` and
`OptParse.render_helpdoc`. It does not decide when help should be shown; it only
derives and renders the focused help page for the given parser and argument
vector.

This is useful if you want to handle `--help`, help subcommands, or other
application-specific help triggers yourself while still reusing OptParse's help
generation.

# Keyword Arguments
- `progname::AbstractString = ""`: Program name prefix to render in the usage line

# Examples
```jldoctest
julia> using OptParse

julia> parser = command("serve", record((
           host = option("--host", str("HOST")),
           verbose = flag("-v", "--verbose"),
       )));

julia> print(OptParse.generate_help(parser, ["serve"]; progname = "prog"))

Usage: prog serve --host <HOST> [OPTIONS]

Options:
   --host <HOST>
   [--verbose]

```

# See Also
- `build_help_doc`
- [`optparse`](@ref)
- [`tryoptparse`](@ref)
"""
generate_help(parser, argv; progname = "") = render_helpdoc(build_help_doc(parser, argv); progname)

"""
    print_help(io, parser, argv; progname = "")

Render and print the focused help page for `argv` from `parser`.

This is a small convenience wrapper around [`generate_help`](@ref). It is useful
when you want to route help output to a chosen `IO` stream, such as `stdout`,
`stderr`, or an in-memory buffer.

# Keyword Arguments
- `progname::AbstractString = ""`: Program name prefix to render in the usage line

# Returns
Returns `nothing` after writing the rendered help text to `io`.

# See Also
- [`generate_help`](@ref)
- [`build_help_doc`](@ref)
- [`runparse`](@ref)
"""
function print_help(io, parser, argv; progname = "")
    helpstr = generate_help(parser, argv; progname)
    print(io, helpstr)
    return nothing
end

"""
    tryoptparse(parser, argv)

Lower-level parsing entrypoint.

Returns a result container containing either the parsed value or a structured parse failure.
Unlike [`optparse`](@ref), this function does not throw on parse failures.
"""
function tryoptparse(pp::AbstractParser{T, S}, args::Vector{String})::ParseResult{T} where {T, S}

    canonical_argv, _ = normalize_argv(args)
    ctx = Context{S}(buffer = canonical_argv, state = pp.initialState, usage = @unionsplit usage(pp))

    while true
        mayberesult::InnerParseResult{S} = @unionsplit parse(pp, ctx)

        if is_error(mayberesult)
            return typedErr(unwrap_error(mayberesult).error)
        end
        result = unwrap(mayberesult)

        previous_buffer = ctx_remaining(ctx)
        ctx = res_nextctx(result)

        if no_progress(previous_buffer, ctx)
            # Top-level progress guard: a parser must not report success while leaving argv unchanged.
            return typedErr(T, main_error(MAIN_NoProgress; token = ctx_peek(ctx)))
        end

        ctx_length(ctx) > 0 || break
    end

    state = ctx_state(ctx)

    ret = @unionsplit complete(pp, state)
    return ret
end


"""
    optparse(parser, argv)

High-level parsing entrypoint.

This function has two modes controlled through the `juliac` preference loaded
via `Preferences.jl`:

- in normal Julia runtime usage, it returns the parsed value and throws
  [`ParseException`](@ref) on failure
- when `juliac` mode is enabled, it renders the error to `stderr` and returns
  `nothing` on failure instead of throwing

If you need stable non-throwing behavior across environments, use
[`tryoptparse`](@ref) instead.
"""
function optparse(pp::AbstractParser{T}, args::Vector{String}) where {T}
    mayberes = tryoptparse(pp, args)::ParseResult{T}

    if is_error(mayberes)
        @static if juliac
            errmsg = sprint(
                showerror, ParseException(
                    pp, args, unwrap_error(mayberes)
                )
            )
            print(Core.stderr, "Error: ")
            println(Core.stderr, errmsg)
            return nothing
        else
            throw(
                ParseException(
                    pp, args, unwrap_error(mayberes)
                )
            )
        end
    end

    return unwrap(mayberes)
end

"""
    runparse(parser, argv; progname = "", help_command = "help", help_flags = ["--help"], on_empty = ...)

Application-facing parsing entrypoint with built-in help handling.

`runparse` layers a small CLI policy on top of [`optparse`](@ref):

- help flags such as `--help` are detected lexically and cause focused help to
  be rendered for the current invocation
- an explicit help subcommand is injected at the top level using
  [`helpcommand`](@ref)
- empty invocations can be rewritten to a caller-chosen fallback argument vector

When the invocation resolves to help, `runparse` prints the rendered help page
to `stderr` and returns `nothing`. Otherwise it behaves like [`optparse`](@ref)
on the effective argument vector.

# Keyword Arguments
- `progname::AbstractString = ""`: Program name prefix to render in help output
- `help_command::String = "help"`: Top-level positional help command to inject.
  Pass `""` to disable positional help injection.
- `help_flags::Vector{String} = ["--help"]`: Flag tokens that request help for
  the current invocation
- `on_empty = isempty(help_command) ? [] : [help_command]`: Replacement argv to
  use when `argv` is empty. This lets bare invocation show help or dispatch to a
  default command.

# Notes
- Help flags are recognized only before `--`
- Positional help is implemented by parsing an injected hidden help branch, but
  help is rendered from the original parser

# See Also
- [`optparse`](@ref)
- [`tryoptparse`](@ref)
- [`helpcommand`](@ref)
- [`print_help`](@ref)
"""
function runparse(
        parser::AbstractParser, argv::Vector{String};
        progname = "",
        help_command = "help",
        help_flags = ["--help"],
        on_empty = isempty(help_command) ? [] : [help_command]
    )

    if isempty(argv)
        argv = on_empty
    end

    # scan the input buffer for help flags.
    # if present, record presence, filter them and
    # ask for help on the remaining tokens
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

    # inject the helpcommand (only if provided)
    if !isempty(help_command)
        _parser = or(hidden(helpcommand(help_command)), parser)
        res = optparse(_parser, newargv)
        if res isa HelpRequest
            # important: we generate the help on the original parser!
            print_help(Core.stderr, parser, res.argv; progname)
            return nothing
        end
        return res
    else
        return optparse(parser, newargv)
    end
end

end # module OptParse
