using Test
using OptParse
using OptParse:
    Context,
    Parser,
    as_tuple,
    as_vector,
    complete,
    consumed_empty,
    ctx_optterm,
    ctx_path,
    ctx_remaining,
    ctx_state,
    ctx_with_options_terminated,
    ctx_with_path,
    metavar,
    parse,
    priority,
    res_consumed,
    res_nextctx,
    res_num_consumed,
    tstate,
    tval,
    usage_alternative_branch,
    usage_command_boundary,
    usage_tuple_child,
    widen_state


using ErrorTypes
using WrappedUnions: @unionsplit, unwrap as unwrapunion
using JET
using UUIDs

# define it here for ease of use
splitparse(p::Parser, ctx::Context) = @unionsplit parse(p, ctx)
splitcomplete(p::Parser, st) = @unionsplit complete(p, st)
function mkctx(buffer::Vector{String}, state; options_terminated::Bool=false, path=nothing)
    ctx = Context(; buffer, state)
    options_terminated && (ctx = ctx_with_options_terminated(ctx, true))
    !isnothing(path) && (ctx = ctx_with_path(ctx, path))
    return ctx
end
res_nextstate(succ) = ctx_state(res_nextctx(succ))
val(::Val{x}) where {x} = x

parse_ok(p, argv) = unwrap(tryoptparse(p, argv))

function parse_fail(p, argv)
    result = tryoptparse(p, argv)
    @test is_error(result)
    return unwrap_error(result)
end

render_fail(p, argv) = sprint() do io
    OptParse.render_error(io, parse_fail(p, argv))
end

macro test_parse_error(parser, argv, domain, code)
    quote
        err = parse_fail($(esc(parser)), $(esc(argv)))
        _code = $(esc(code))
        @test err.domain == $(esc(domain))
        @test typeof(_code)(err.code) == _code
        err
    end
end
