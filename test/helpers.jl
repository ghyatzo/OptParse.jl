using Test
using OptParse
using OptParse:
    AbstractParser,
    Context,
    as_tuple,
    complete,
    consumed_empty,
    options_terminated,
    remaining,
    state,
    with_options_terminated,
    metavar,
    parse,
    priority,
    res_consumed,
    res_nextctx,
    res_nextstate,
    res_num_consumed,
    state_t,
    val_t,
    widen_state


using OptParse.SumResults
using WrappedUnions: @unionsplit, unwrap as unwrapunion
using JET
using UUIDs
using ExprTools: splitdef

# define it here for ease of use
splitparse(p::AbstractParser, ctx::Context) = parse(p, ctx)
splitcomplete(p::AbstractParser, st) = complete(p, st)
function mkctx(buffer::Vector{String}, state; options_terminated::Bool = false)
    ctx = Context(; buffer, state)
    options_terminated && (ctx = with_options_terminated(ctx, true))
    return ctx
end
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

macro test_parse_error(parser, argv, errtype, code)
    return quote
        err = parse_fail($(esc(parser)), $(esc(argv)))
        @test err isa $(esc(errtype))
        @test err.code == $(esc(code))
        err
    end
end
