struct TestConfig
    host::String
    port::Int
end

struct TestPoint
    x::Int
    y::Int
end

struct PositiveOnly
    value::Int

    function PositiveOnly(value::Int)
        value > 0 || throw(ArgumentError("value must be positive"))
        return new(value)
    end
end

@testset "should preserve wrapped parser priority and state" begin
    baseParser = record((verbose = switch("-v"),))
    parser = construct(TestConfig, (
        host = default(option("--host", str()), "localhost"),
        port = default(option("--port", integer()), 8080),
    ))

    @test priority(parser) == priority(parser.parser)
    @test parser.initialState === parser.parser.initialState
    @test tstate(parser) === tstate(parser.parser)
    @test baseParser isa AbstractParser
end

@testset "should construct a struct from a record parser" begin
    parser = construct(TestConfig, (
        host = option("--host", str("HOST")),
        port = option("--port", integer("PORT")),
    ))

    value = parse_ok(parser, ["--host", "localhost", "--port", "8080"])
    @test value == TestConfig("localhost", 8080)
end

@testset "should construct a struct from a sequence parser" begin
    parser = construct(TestPoint, (
        arg(integer("X")),
        arg(integer("Y")),
    ))

    value = parse_ok(parser, ["10", "20"])
    @test value == TestPoint(10, 20)
end

@testset "should surface construction failures as parse errors" begin
    parser = construct(PositiveOnly, (
        value = option("--value", integer("VALUE")),
    ))

    err = parse_fail(parser, ["--value", "-1"])
    @test err.domain == OptParse.ERR_ModConstruct
    @test OptParse.ConstructErrCode(err.code) == OptParse.CONSTRUCT_MakeFailed
    @test occursin("PositiveOnly", err.token)
    @test occursin("field names and types", err.detail)
end

@testset "should pretty print constructed records with field parsers" begin
    parser = construct(TestConfig, (
        host = option("--host", str("HOST")),
        port = flag("--port"),
    ))

    compact = repr(parser)
    pretty = sprint(show, MIME"text/plain"(), parser)

    @test occursin("construct(Main.TestConfig, record(", compact)
    @test occursin("TestConfig", pretty)
    @test occursin("host: option(--host, str(HOST))", pretty)
    @test occursin("port: flag(--port)", pretty)
end
