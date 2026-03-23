@testset "should create a parser that expects a single argument" begin
    parser = argument(str(; metavar = "FILE"))

    @test priority(parser) == 5
    @test getproperty(unwrapunion(parser), :initialState) === none(OptParse.ParseResult{String})
end

@testset "should parse a string argument" begin
    parser = argument(str(; metavar = "FILE"))
    state = parser.initialState
    buffer = ["myfile.txt"]
    ctx = Context(;buffer, state)

    res = splitparse(parser, ctx)
    @test !is_error(res)

    succ = unwrap(res)
    next = ℒ_nextctx(succ)

    st = ℒ_state(next)
    @test !is_error(unwrap(st))
    @test unwrap(unwrap(st)) == "myfile.txt"

    @test ctx_remaining(next) == String[]
    @test as_tuple(ℒ_consumed(succ)) == ("myfile.txt",)
end

@testset "should parse an integer argument" begin
    parser = argument(integer(; min = 0))
    state = parser.initialState
    buffer = ["42"]
    ctx = Context(;buffer, state)

    res = splitparse(parser, ctx)
    @test !is_error(res)

    succ = unwrap(res)
    next = ℒ_nextctx(succ)

    st = ℒ_state(next)
    @test !is_error(unwrap(st))
    @test unwrap(unwrap(st)) == 42

    @test ctx_remaining(next) == String[]
    @test as_tuple(ℒ_consumed(succ)) == ("42",)
end

@testset "should fail when buffer is empty" begin
    parser = argument(str(; metavar = "FILE"))
    state = parser.initialState
    buffer = String[]
    ctx = Context(; buffer, state)

    res = splitparse(parser, ctx)
    @test is_error(res)

    err = unwrap_error(res)
    @test ℒ_nconsumed(err) == 0
    @test err.error.domain == OptParse.ERR_ArgArgument
    @test OptParse.ArgumentErrCode(err.error.code) == OptParse.ARGUMENT_EndOfInput
end

@testset "should propagate value parser failures" begin
    parser = argument(integer(; min = 1, max = 100))
    state = getproperty(unwrapunion(parser), :initialState)
    buffer = ["invalid"]
    ctx = Context(;buffer, state)

    res = splitparse(parser, ctx)
    @test !is_error(res)

    succ = unwrap(res)
    st = ℒ_nextstate(succ)
    @test st !== nothing
    @test is_error(unwrap(st))
    err = unwrap_error(unwrap(st))
    @test err.domain == OptParse.ERR_IntegerVal
    @test OptParse.IntegerErrCode(err.code) == OptParse.INTEGER_Invalid
end

@testset "should complete successfully with valid state" begin
    parser = argument(str(; metavar = "FILE"))
    validState = some(OptParse.ParseResult{String}(Ok("test.txt")))

    res = splitcomplete(parser, validState)
    @test !is_error(res)
    @test unwrap(res) == "test.txt"
end

@testset "should fail completion with invalid state" begin
    parser = argument(str(; pattern = r"^A+$", metavar = "FILE"))
    invalidState = some(str(; pattern = r"^A+$")("bbb"))

    res = splitcomplete(parser, invalidState)
    @test is_error(res)
    err = unwrap_error(res)
    @test err.domain == OptParse.ERR_StringVal
    @test OptParse.StringErrCode(err.code) == OptParse.STRING_InvalidPattern
end

@testset "should work with different value parser constraints" begin
    fileParser = argument(str(; pattern = r"\.(txt|md)$"))
    portParser = argument(integer(; min = 1024, max = 0xffff))

    @test parse_ok(fileParser, ["readme.txt"]) == "readme.txt"
    @test parse_fail(fileParser, ["script.js"]).domain == OptParse.ERR_StringVal

    @test parse_ok(portParser, ["8080"]) == 8080
    @test parse_fail(portParser, ["80"]).domain == OptParse.ERR_IntegerVal
end

@testset "should handle -- edge cases correctly" begin
    parser = argument(str())

    @test parse_ok(parser, ["--", "abc"]) == "abc"

    ctx = Context(buffer=["abc", "--"], state=parser.initialState)
    presult = splitparse(parser, ctx)
    @test !is_error(presult)
    
    pok = unwrap(presult)
    @test as_tuple(ℒ_consumed(pok)) == ("abc",)
    @test ctx_remaining(ℒ_nextctx(pok)) == ["--"]

    val = splitcomplete(parser, ℒ_nextstate(pok))
    @test (@? val) == "abc"

    err = @test_parse_error parser ["--"] OptParse.ERR_ArgArgument OptParse.ARGUMENT_EndOfInput
    @test err.detail == "STRING"
end

@testset "should be type stable" begin
    @test_opt argument(str(; pattern = r"\.(txt|md)$"))
    fileParser = argument(str(; pattern = r"\.(txt|md)$"))
    @test_opt argument(integer(; min = 1024, max = 0xffff))
    portParser = argument(integer(; min = 1024, max = 0xffff))

    @test_opt argparse(fileParser, ["readme.txt"])
    @test_opt argparse(portParser, ["8080"])
end
