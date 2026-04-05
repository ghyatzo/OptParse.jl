@testset "should error with short names longer than 1 character" begin
    @test_throws ArgumentError option("-port", integer())
end

@testset "should error with options not starting with - or --" begin
    @test_throws ArgumentError option("port", integer())
    @test_throws ArgumentError option("?port", integer())
    @test_throws ArgumentError option("/port", integer())
    @test_throws ArgumentError option("---port", integer())
end

@testset "should parse option with separated value" begin
    parser = option(("-p", "--port"), integer())
    context = Context(buffer=["--port", "8080"], state=parser.initialState)

    res = splitparse(parser, context)

    @test !is_error(res)
    ps = unwrap(res)

    # next.state should itself be a successful value (Result/Option)
    @test !is_error(ℒ_nextstate(ps))
    @test unwrap(ℒ_nextstate(ps)) == 8080

    # buffer consumed
    @test ctx_remaining(ps.next) == String[]
    # tuple, not Vector
    @test as_tuple(ℒ_consumed(ps)) == ("--port", "8080")
end

@testset "should parse option with equals-separated value" begin
    parser = option("--port", integer())
    context = Context(buffer=["--port=8080"], state=parser.initialState)

    res = splitparse(parser, context)

    @test !is_error(res)
    ps = unwrap(res)

    @test !is_error(ℒ_nextstate(ps))
    @test unwrap(ℒ_nextstate(ps)) == 8080

    @test ctx_remaining(ℒ_nextctx(ps)) == String[]
    @test as_tuple(ℒ_consumed(ps)) == ("--port=8080",)
end

@testset "should handle option terminator edge cases correctly" begin
    parser = option("--name", str())

    @test_parse_error parser ["--", "--name", "lol"] OptParse.ERR_ArgOption OptParse.OPTION_NoMoreOptions
    @test_parse_error parser ["--"] OptParse.ERR_ArgOption OptParse.OPTION_Missing
    @test_parse_error parser ["--name", "--"] OptParse.ERR_ArgOption OptParse.OPTION_MissingValue
    @test parse_ok(parser, ["--name", "bob", "--"]) == "bob"
end

# @testset "should parse DOS-style option with colon" begin
#     parser  = option("/P", integer())
#     context = Context(buffer=["/P:8080"], state=parser.initialState)

#     res = splitparse(parser, context)

#     @test !is_error(res)
#     ps = unwrap(res)

#     @test !is_error(ℒ_nextstate(ps))
#     @test unwrap(ℒ_nextstate(ps)) == 8080
#     # TS test does not check buffer/consumed here
# end

@testset "should fail when value is missing" begin
    parser = option("--port", integer())
    context = Context(buffer=["--port"], state=parser.initialState)

    res = splitparse(parser, context)

    @test is_error(res)
    pf = unwrap_error(res)

    @test ℒ_consumed(pf) == 1
    @test pf.error.domain == OptParse.ERR_ArgOption
    @test OptParse.OptionErrCode(pf.error.code) == OptParse.OPTION_MissingValue
    @test pf.error.token == "--port"
end

@testset "should parse string values" begin
    parser = option("--name", str(; metavar = "NAME"))
    context = Context(buffer=["--name", "Alice"], state=parser.initialState)

    res = splitparse(parser, context)

    @test !is_error(res)
    ps = unwrap(res)

    @test !is_error(ℒ_nextstate(ps))
    @test unwrap(ℒ_nextstate(ps)) == "Alice"
end

@testset "should propagate value parser failures" begin
    parser = option("--port", integer(; min = 1, max = 0xffff))
    context = Context(buffer=["--port", "invalid"], state=parser.initialState)

    res = splitparse(parser, context)

    # Option itself matched, so overall parse succeeds...
    @test !is_error(res)
    ps = unwrap(res)

    # ...but the inner value parser failed (carry failure in state)
    @test is_error(ℒ_nextstate(ps))
    err = unwrap_error(ℒ_nextstate(ps))
    @test err.domain == OptParse.ERR_IntegerVal
    @test OptParse.IntegerErrCode(err.code) == OptParse.INTEGER_Invalid
    @test err.token == "invalid"
end

@testset "should fail on unmatched option" begin
    parser = option(("-v", "--verbose"), choice(["yes", "no"]))
    context = Context(buffer=["--help"], state=parser.initialState)

    res = splitparse(parser, context)

    @test is_error(res)
    pf = unwrap_error(res)

    @test ℒ_consumed(pf) == 0
    @test pf.error.domain == OptParse.ERR_ArgOption
    @test OptParse.OptionErrCode(pf.error.code) == OptParse.OPTION_NoMatch
    @test pf.error.token == "--help"
end

@testset "should be type stable" begin
    @test_opt option("--port", integer())
    parser = option("--port", integer())

    @test_opt argparse(parser, ["--port", "8080"])
end
