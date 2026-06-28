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

@parser struct MacroConfig
    @description "Macro parser description"
    "Host"
    host = option("--host", str("HOST"))
    "Port"
    port = option("--port", integer("PORT"))
    @footer "Macro parser footer"
end

const macro_desc_var = "Macro parser description from variable"
const macro_footer_help = help(; footer = "Macro parser footer from help modifier")

@parser struct MacroConfigFromValues
    @description macro_desc_var
    "Host"
    host = option("--host", str("HOST"))
    "Port"
    port = option("--port", integer("PORT"))
    macro_footer_help
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
    macro_parser = lift(MacroConfig)
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

@parser struct OrderConfig
    @description "first description"
    @footer "first footer"
    "Value"
    value = option("--value", integer("VALUE"))
    @description "second description"
end

const factored_mod = help("Brief", description = "factored description", footer = "factored footer")

@parser struct FactoredConfig
    factored_mod
    "Value"
    value = option("--value", integer("VALUE"))
end

@testset "parser macro should accept non-literal parser help expressions" begin
    macro_parser_with_values = lift(MacroConfigFromValues)
    value = parse_ok(macro_parser_with_values, ["--host", "localhost", "--port", "8080"])
    @test value == MacroConfigFromValues("localhost", 8080)

    helptext = OptParse.generate_help(macro_parser_with_values, String[]; progname = "prog")
    @test occursin(macro_desc_var, helptext)
    @test occursin("Macro parser footer from help modifier", helptext)
end

@testset "parser macro should apply @description and @footer in source order" begin
    order_parser = lift(OrderConfig)
    info = order_parser.info
    @test info.description == "second description"
    @test info.footer == "first footer"
    @test parse_ok(order_parser, ["--value", "7"]) == OrderConfig(7)
end

@testset "parser macro should reject misplaced bare strings" begin
    @test_throws ArgumentError @macroexpand(@parser struct BadTrailing
        "Value"
        value = option("--value", integer("VALUE"))
        "stray trailing string"
    end)

    @test_throws ArgumentError @macroexpand(@parser struct BadLeading
        "stray leading string"
        "Value"
        value = option("--value", integer("VALUE"))
    end)
end

@testset "parser macro should reject unknown markers" begin
    @test_throws ArgumentError @macroexpand(@parser struct BadMarker
        @bogus "nope"
        value = option("--value", integer("VALUE"))
    end)
end

@testset "parser macro should accept a bare modifier expression" begin
    factored_parser = lift(FactoredConfig)
    info = factored_parser.info
    @test info.brief == "Brief"
    @test info.description == "factored description"
    @test info.footer == "factored footer"
    @test parse_ok(factored_parser, ["--value", "3"]) == FactoredConfig(3)
end

@testset "parser macro should register a LiftedParser with lift and type-based entrypoints" begin
    @test MacroConfig <: AbstractLiftedParser
    @test FactoredConfig <: AbstractLiftedParser

    p = lift(MacroConfig)
    @test p isa AbstractParser
    @test valuetype(p) == MacroConfig

    result = optparse(MacroConfig, ["--host", "x", "--port", "9"])
    @test result == MacroConfig("x", 9)

    tres = tryoptparse(MacroConfig, ["--host", "x", "--port", "9"])
    @test !is_error(tres)
    @test unwrap(tres) == MacroConfig("x", 9)
end
