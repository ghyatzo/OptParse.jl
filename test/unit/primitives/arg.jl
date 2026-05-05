@testset "should create a parser that expects a single argument" begin
    parser = arg(str(; metavar = "FILE"))

    @test priority(parser) == 5
    @test getproperty((parser), :initialState) === none(OptParse.ParseResult{String})
end

@testset "should parse a string argument" begin
    parser = arg(str(; metavar = "FILE"))
    state = parser.initialState
    buffer = ["myfile.txt"]
    ctx = mkctx(buffer, state)

    res = splitparse(parser, ctx)
    @test !is_error(res)

    succ = unwrap(res)
    next = res_nextctx(succ)

    st = ctx_state(next)
    @test !is_error(unwrap(st))
    @test unwrap(unwrap(st)) == "myfile.txt"

    @test ctx_remaining(next) == String[]
    @test as_tuple(res_consumed(succ)) == ("myfile.txt",)
end

@testset "should parse an integer argument" begin
    parser = arg(integer(; min = 0))
    state = parser.initialState
    buffer = ["42"]
    ctx = mkctx(buffer, state)

    res = splitparse(parser, ctx)
    @test !is_error(res)

    succ = unwrap(res)
    next = res_nextctx(succ)

    st = ctx_state(next)
    @test !is_error(unwrap(st))
    @test unwrap(unwrap(st)) == 42

    @test ctx_remaining(next) == String[]
    @test as_tuple(res_consumed(succ)) == ("42",)
end

@testset "should fail when buffer is empty" begin
    parser = arg(str(; metavar = "FILE"))
    state = parser.initialState
    buffer = String[]
    ctx = mkctx(buffer, state)

    res = splitparse(parser, ctx)
    @test is_error(res)

    err = unwrap_error(res)
    @test res_num_consumed(err) == 0
    @test err.error.domain == OptParse.ERR_ArgArgument
    @test OptParse.ArgumentErrCode(err.error.code) == OptParse.ARGUMENT_EndOfInput
end

@testset "should propagate value parser failures" begin
    parser = arg(integer(; min = 1, max = 100))
    state = getproperty((parser), :initialState)
    buffer = ["invalid"]
    ctx = mkctx(buffer, state)

    res = splitparse(parser, ctx)
    @test !is_error(res)

    succ = unwrap(res)
    st = res_nextstate(succ)
    @test st !== nothing
    @test is_error(unwrap(st))
    err = unwrap_error(unwrap(st))
    @test err.domain == OptParse.ERR_IntegerVal
    @test OptParse.IntegerErrCode(err.code) == OptParse.INTEGER_Invalid
end

@testset "should complete successfully with valid state" begin
    parser = arg(str(; metavar = "FILE"))
    validState = some(OptParse.ParseResult{String}(Ok("test.txt")))

    res = splitcomplete(parser, validState)
    @test !is_error(res)
    @test unwrap(res) == "test.txt"
end

@testset "should fail completion with invalid state" begin
    parser = arg(str(; pattern = r"^A+$", metavar = "FILE"))
    invalidState = some(str(; pattern = r"^A+$")("bbb"))

    res = splitcomplete(parser, invalidState)
    @test is_error(res)
    err = unwrap_error(res)
    @test err.domain == OptParse.ERR_StringVal
    @test OptParse.StringErrCode(err.code) == OptParse.STRING_InvalidPattern
end

@testset "should work with different value parser constraints" begin
    fileParser = arg(str(; pattern = r"\.(txt|md)$"))
    portParser = arg(integer(; min = 1024, max = 0xffff))

    # valid file
    @test parse_ok(fileParser, ["readme.txt"]) == "readme.txt"
    # invalid file
    @test parse_fail(fileParser, ["script.js"]).domain == OptParse.ERR_StringVal

    # valid port
    @test parse_ok(portParser, ["8080"]) == 8080
    # invalid port
    @test parse_fail(portParser, ["80"]).domain == OptParse.ERR_IntegerVal
end

@testset "should handle -- edge cases correctly" begin
    parser = arg(str())

    @test parse_ok(parser, ["--", "abc"]) == "abc"

    ctx = mkctx(["abc", "--"], parser.initialState)
    presult = splitparse(parser, ctx)
    @test !is_error(presult)

    pok = unwrap(presult)
    @test as_tuple(res_consumed(pok)) == ("abc",)
    @test ctx_remaining(res_nextctx(pok)) == ["--"]

    val = splitcomplete(parser, res_nextstate(pok))
    @test (@? val) == "abc"

    err = @test_parse_error parser ["--"] OptParse.ERR_ArgArgument OptParse.ARGUMENT_EndOfInput
    @test err.detail == "STRING"
end

@testset "should be type stable" begin
    @test_opt arg(str(; pattern = r"\.(txt|md)$"))
    fileParser = arg(str(; pattern = r"\.(txt|md)$"))
    @test_opt arg(integer(; min = 1024, max = 0xffff))
    portParser = arg(integer(; min = 1024, max = 0xffff))

    @test_opt optparse(fileParser, ["readme.txt"])
    @test_opt optparse(portParser, ["8080"])
end
