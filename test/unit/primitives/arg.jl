@testset "should create a parser that expects a single argument" begin
    parser = arg(str(; metavar = "FILE"))

    @test priority(parser) == 5
    @test parser.initialState == OptParse.ArgumentState{String, OptParse.StringValError}'.NotMatched
end

@testset "should parse a string argument" begin
    parser = arg(str(; metavar = "FILE"))
    istate = parser.initialState
    buffer = ["myfile.txt"]
    ctx = mkctx(buffer, istate)

    res = splitparse(parser, ctx)
    @test !is_error(res)

    succ = unwrap(res)
    next = res_nextctx(succ)

    st = state(next)
    @test st == OptParse.ArgumentState{String, OptParse.StringValError}'.Matched("myfile.txt")

    @test remaining(next) == String[]
    @test as_tuple(res_consumed(succ)) == ("myfile.txt",)
end

@testset "should parse an integer argument" begin
    parser = arg(integer(; min = 0))
    istate = parser.initialState
    buffer = ["42"]
    ctx = mkctx(buffer, istate)

    res = splitparse(parser, ctx)
    @test !is_error(res)

    succ = unwrap(res)
    next = res_nextctx(succ)

    st = state(next)
    @test st == OptParse.ArgumentState{Int, OptParse.IntegerValError}'.Matched(42)

    @test remaining(next) == String[]
    @test as_tuple(res_consumed(succ)) == ("42",)
end

@testset "should fail when buffer is empty" begin
    parser = arg(str(; metavar = "FILE"))
    istate = parser.initialState
    buffer = String[]
    ctx = mkctx(buffer, istate)

    res = splitparse(parser, ctx)
    @test is_error(res)

    err = unwrap_error(res)
    @test res_num_consumed(err) == 0
    @test err.error isa OptParse.ArgArgumentError
    @test err.error.code == OptParse.ARGUMENT_EndOfInput
end

@testset "should propagate value parser failures" begin
    parser = arg(integer(; min = 1, max = 100))
    istate = getproperty((parser), :initialState)
    buffer = ["invalid"]
    ctx = mkctx(buffer, istate)

    res = splitparse(parser, ctx)
    @test !is_error(res)

    succ = unwrap(res)
    st = res_nextstate(succ)
    err = unwrap_error(integer(; min = 1, max = 100)("invalid"))
    @test st == OptParse.ArgumentState{Int, OptParse.IntegerValError}'.Invalid(err)
    completed = splitcomplete(parser, st)
    @test is_error(completed)
    @test unwrap_error(completed) === err
    @test err.code == OptParse.INTEGER_Invalid
end

@testset "should complete successfully with valid state" begin
    parser = arg(str(; metavar = "FILE"))
    validState = OptParse.ArgumentState{String, OptParse.StringValError}'.Matched("test.txt")

    res = splitcomplete(parser, validState)
    @test !is_error(res)
    @test unwrap(res) == "test.txt"
end

@testset "should fail completion with invalid state" begin
    parser = arg(str(; pattern = r"^A+$", metavar = "FILE"))
    invalidState = OptParse.ArgumentState{String, OptParse.StringValError}'.Invalid(
        unwrap_error(str(; pattern = r"^A+$")("bbb"))
    )

    res = splitcomplete(parser, invalidState)
    @test is_error(res)
    err = unwrap_error(res)
    @test err isa OptParse.StringValError
    @test err.code == OptParse.STRING_InvalidPattern
end

@testset "should fail completion when not matched" begin
    parser = arg(str("FILE"))
    result = splitcomplete(parser, parser.initialState)
    @test is_error(result)
    err = unwrap_error(result)
    @test err.code == OptParse.ARGUMENT_TooFew
    @test err.detail == "FILE"
end

@testset "should reject duplicates after valid or invalid input" begin
    parser = arg(integer())
    for token in ("42", "invalid"), terminated in (false, true)
        first_result = splitparse(parser, mkctx([token], parser.initialState))
        @test !is_error(first_result)
        st = res_nextstate(unwrap(first_result))
        buffer = terminated ? ["--", "43"] : ["43"]
        result = splitparse(parser, mkctx(buffer, st))
        @test is_error(result)
        err = unwrap_error(result)
        @test err.error.code == OptParse.ARGUMENT_Duplicate
        @test res_num_consumed(err) == 0
    end
end

@testset "should work with different value parser constraints" begin
    fileParser = arg(str(; pattern = r"\.(txt|md)$"))
    portParser = arg(integer(; min = 1024, max = 0xffff))

    # valid file
    @test parse_ok(fileParser, ["readme.txt"]) == "readme.txt"
    # invalid file
    @test parse_fail(fileParser, ["script.js"]) isa OptParse.StringValError

    # valid port
    @test parse_ok(portParser, ["8080"]) == 8080
    # invalid port
    @test parse_fail(portParser, ["80"]) isa OptParse.IntegerValError
end

@testset "should handle -- edge cases correctly" begin
    parser = arg(str())

    @test parse_ok(parser, ["--", "abc"]) == "abc"

    ctx = mkctx(["abc", "--"], parser.initialState)
    presult = splitparse(parser, ctx)
    @test !is_error(presult)

    pok = unwrap(presult)
    @test as_tuple(res_consumed(pok)) == ("abc",)
    @test remaining(res_nextctx(pok)) == ["--"]

    val = splitcomplete(parser, res_nextstate(pok))
    @test (@? val) == "abc"

    err = @test_parse_error parser ["--"] OptParse.ArgArgumentError OptParse.ARGUMENT_EndOfInput
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
