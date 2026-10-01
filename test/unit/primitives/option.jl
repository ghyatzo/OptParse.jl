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
    context = mkctx(["--port", "8080"], parser.initialState)

    res = splitparse(parser, context)

    @test !is_error(res)
    ps = unwrap(res)

    @test res_nextstate(ps) == OptParse.OptionState{Int, OptParse.IntegerValError}'.Matched(8080)

    # buffer consumed
    @test remaining(res_nextctx(ps)) == String[]
    # tuple, not Vector
    @test as_tuple(res_consumed(ps)) == ("--port", "8080")
end

@testset "should parse option with equals-separated value" begin
    parser = option("--port", integer())
    context = mkctx(["--port=8080"], parser.initialState)

    res = splitparse(parser, context)

    @test !is_error(res)
    ps = unwrap(res)

    @test res_nextstate(ps) == OptParse.OptionState{Int, OptParse.IntegerValError}'.Matched(8080)

    @test remaining(res_nextctx(ps)) == String[]
    @test as_tuple(res_consumed(ps)) == ("--port=8080",)
end

@testset "should correctly parse negative integers" begin
    p = option("--opt", integer())

    @test parse_ok(p, ["--opt", "-1000"]) == -1000
end

@testset "should handle option terminator edge cases correctly" begin
    parser = option("--name", str())

    @test_parse_error parser ["--", "--name", "lol"] OptParse.ArgOptionError OptParse.OPTION_NoMoreOptions
    @test_parse_error parser ["--"] OptParse.ArgOptionError OptParse.OPTION_Missing
    @test_parse_error parser ["--name", "--"] OptParse.ArgOptionError OptParse.OPTION_MissingValue
    @test parse_ok(parser, ["--name", "bob", "--"]) == "bob"
end

# @testset "should parse DOS-style option with colon" begin
#     parser  = option("/P", integer())
#     context = Context(buffer=["/P:8080"], state=parser.initialState)

#     res = splitparse(parser, context)

#     @test !is_error(res)
#     ps = unwrap(res)

#     @test !is_error(res_nextstate(ps))
#     @test unwrap(res_nextstate(ps)) == 8080
#     # TS test does not check buffer/consumed here
# end

@testset "should fail when value is missing" begin
    parser = option("--port", integer())
    context = mkctx(["--port"], parser.initialState)

    res = splitparse(parser, context)

    @test is_error(res)
    pf = unwrap_error(res)

    @test res_num_consumed(pf) == 1
    @test pf.error isa OptParse.ArgOptionError
    @test pf.error.code == OptParse.OPTION_MissingValue
    @test pf.error.token == "--port"
end

@testset "should parse string values" begin
    parser = option("--name", str(; metavar = "NAME"))
    context = mkctx(["--name", "Alice"], parser.initialState)

    res = splitparse(parser, context)

    @test !is_error(res)
    ps = unwrap(res)

    @test res_nextstate(ps) == OptParse.OptionState{String, OptParse.StringValError}'.Matched("Alice")
end

@testset "should fail on ambiguous flaglike string values" begin
    parser = option("--port", str())
    context = mkctx(["--port", "-a"], parser.initialState)

    res = splitparse(parser, context)

    @test is_error(res)
    pf = unwrap_error(res)

    @test res_num_consumed(pf) == 1
    @test pf.error isa OptParse.ArgOptionError
    @test pf.error.code == OptParse.OPTION_AmbiguousValue
    @test pf.error.token == "--port"
    @test pf.error.detail == "-a"

end

@testset "should propagate value parser failures" begin
    parser = option("--port", integer(; min = 1, max = 0xffff))
    for buffer in (["--port", "invalid"], ["--port=invalid"])
        res = splitparse(parser, mkctx(buffer, parser.initialState))
        @test !is_error(res)
        ps = unwrap(res)
        st = res_nextstate(ps)
        completed = splitcomplete(parser, st)
        @test is_error(completed)
        err = unwrap_error(completed)
        @test st == OptParse.OptionState{Int, OptParse.IntegerValError}'.Invalid(err)
        @test err.code == OptParse.INTEGER_Invalid
        @test err.token == "invalid"
        @test remaining(res_nextctx(ps)) == String[]
        @test as_tuple(res_consumed(ps)) == Tuple(buffer)
    end
end

@testset "should complete an unmatched option with a missing error" begin
    parser = option(("-p", "--port"), integer())
    @test parser.initialState == OptParse.OptionState{Int, OptParse.IntegerValError}'.NotMatched
    result = splitcomplete(parser, parser.initialState)
    @test is_error(result)
    err = unwrap_error(result)
    @test err.code == OptParse.OPTION_Missing
    @test sprint(OptParse.render_error, err) == "Missing required option(s): $(Tuple(parser.names))"

    result = splitparse(parser, mkctx(["--"], parser.initialState))
    @test !is_error(result)
    next = res_nextctx(unwrap(result))
    @test state(next) == parser.initialState
    @test options_terminated(next)
end

@testset "should reject duplicates after valid input and allow replacement after invalid input" begin
    parser = option("--port", integer())
    for value in ("8080", "invalid"), first_equals in (false, true), second_equals in (false, true)
        first_buffer = first_equals ? ["--port=$value"] : ["--port", value]
        first_result = splitparse(parser, mkctx(first_buffer, parser.initialState))
        @test !is_error(first_result)
        st = res_nextstate(unwrap(first_result))
        second_buffer = second_equals ? ["--port=42"] : ["--port", "42"]
        result = splitparse(parser, mkctx(second_buffer, st))
        if value == "8080"
            @test is_error(result)
            err = unwrap_error(result)
            @test err.error.code == OptParse.OPTION_Duplicate
            @test err.error.token == "--port"
            @test res_num_consumed(err) == 1
        else
            @test !is_error(result)
            ps = unwrap(result)
            @test res_nextstate(ps) == OptParse.OptionState{Int, OptParse.IntegerValError}'.Matched(42)
            @test unwrap(splitcomplete(parser, res_nextstate(ps))) == 42
            @test as_tuple(res_consumed(ps)) == Tuple(second_buffer)
        end
    end
end

@testset "should fail on unmatched option" begin
    parser = option(("-v", "--verbose"), choice(["yes", "no"]))
    context = mkctx(["--help"], parser.initialState)

    res = splitparse(parser, context)

    @test is_error(res)
    pf = unwrap_error(res)

    @test res_num_consumed(pf) == 0
    @test pf.error isa OptParse.ArgOptionError
    @test pf.error.code == OptParse.OPTION_NoMatch
    @test pf.error.token == "--help"
end

@testset "should be type stable" begin
    @test_opt option("--port", integer())
    parser = option("--port", integer())

    @test_opt optparse(parser, ["--port", "8080"])
end
