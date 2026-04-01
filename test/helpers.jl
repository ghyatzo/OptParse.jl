using Test
using OptParse
using OptParse:
    Context,
    Parser,
    as_tuple,
    as_vector,
    complete,
    consumed_empty,
    ctx_remaining,
    metavar,
    parse,
    priority,
    tstate,
    tval,
    widen_state,
    ℒ_buffer,
    ℒ_consumed,
    ℒ_nconsumed,
    ℒ_nextctx,
    ℒ_nextstate,
    ℒ_optterm,
    ℒ_pos,
    ℒ_state

using ErrorTypes
using WrappedUnions: @unionsplit, unwrap as unwrapunion
using JET
using UUIDs

# define it here for ease of use
splitparse(p::Parser, ctx::Context) = @unionsplit parse(p, ctx)
splitcomplete(p::Parser, st) = @unionsplit complete(p, st)
val(::Val{x}) where {x} = x

parse_ok(p, argv) = unwrap(tryargparse(p, argv))

function parse_fail(p, argv)
    result = tryargparse(p, argv)
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
