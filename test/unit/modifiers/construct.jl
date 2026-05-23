struct TestConfig
    host::String
    port::Int
end

struct TestPoint
    x::Int
    y::Int
end

struct ExactConfig
    host::String
    port::Int
end

struct PositiveOnly
    value::Int

    function PositiveOnly(value::Int)
        value > 0 || throw(ArgumentError("value must be positive"))
        return new(value)
    end
end

const macro_parser = @parser "Macro parser description" MacroConfig begin
    "Host"
    host = option("--host", str("HOST"))
    "Port"
    port = option("--port", integer("PORT"))
end "Macro parser footer"

const macro_desc_var = "Macro parser description from variable"
const macro_footer_help = help(; footer = "Macro parser footer from help modifier")

const macro_parser_with_values = @parser macro_desc_var MacroConfigFromValues begin
    "Host"
    host = option("--host", str("HOST"))
    "Port"
    port = option("--port", integer("PORT"))
end macro_footer_help

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
    @test err isa OptParse.ModConstructError
    @test err.code == OptParse.CONSTRUCT_MakeFailed
    @test occursin("PositiveOnly", err.typename)
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

@testset "should construct exact structs from record parsers" begin
    parser = construct_exact(ExactConfig, (
        host = option("--host", str("HOST")),
        port = option("--port", integer("PORT")),
    ))

    value = parse_ok(parser, ["--host", "localhost", "--port", "8080"])
    @test value == ExactConfig("localhost", 8080)
end

@testset "should construct exact structs from sequence parsers" begin
    parser = construct_exact(TestPoint, (
        arg(integer("X")),
        arg(integer("Y")),
    ))

    value = parse_ok(parser, ["10", "20"])
    @test value == TestPoint(10, 20)
end

@testset "should reject mismatched exact record shapes eagerly" begin
    err = try
        construct_exact(ExactConfig, (
            host = option("--host", str("HOST")),
        ))
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("construct_exact requires record fields", sprint(showerror, err))
end

@testset "should pretty print exact constructed records with field parsers" begin
    parser = construct_exact(ExactConfig, (
        host = option("--host", str("HOST")),
        port = option("--port", integer("PORT")),
    ))

    compact = repr(parser)
    pretty = sprint(show, MIME"text/plain"(), parser)

    @test occursin("construct_exact(Main.ExactConfig, record(", compact)
    @test occursin("ExactConfig", pretty)
    @test occursin("host: option(--host, str(HOST))", pretty)
    @test occursin("port: option(--port, integer(PORT))", pretty)
end

@testset "parser macro should define a struct and return an exact parser" begin
    value = parse_ok(macro_parser, ["--host", "localhost", "--port", "8080"])
    @test value == MacroConfig("localhost", 8080)
    @test fieldtype(MacroConfig, 1) == String
    @test fieldtype(MacroConfig, 2) == Int

    helptext = OptParse.generate_help(macro_parser, String[]; progname = "prog")
    @test occursin("Macro parser description", helptext)
    @test occursin("Macro parser footer", helptext)
    @test occursin("Host", helptext)
    @test occursin("Port", helptext)
end

@testset "parser macro should accept non-literal parser help expressions" begin
    value = parse_ok(macro_parser_with_values, ["--host", "localhost", "--port", "8080"])
    @test value == MacroConfigFromValues("localhost", 8080)

    helptext = OptParse.generate_help(macro_parser_with_values, String[]; progname = "prog")
    @test occursin(macro_desc_var, helptext)
    @test occursin("Macro parser footer from help modifier", helptext)
end
