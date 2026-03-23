@testset "should error with short flags longer than 1 character" begin
    @test_throws ArgumentError flag("-invalid")
end


@testset "should error with flags not starting with - or --" begin
    @test_throws ArgumentError flag("aaa")
    @test_throws ArgumentError flag("?aaa")
    @test_throws ArgumentError flag("/aaa")
    @test_throws ArgumentError flag("---aaa")
end

@testset "should parse single short flag" begin
    parser = flag("-v")
    context = Context(buffer=["-v"], state=parser.initialState)

    result = splitparse(parser, context)

    @test !is_error(result)
    succ = unwrap(result)
    @test is_ok_and(==(true), ℒ_state(ℒ_nextctx(succ)))
    @test ctx_remaining(ℒ_nextctx(succ)) == String[]
    @test as_tuple(ℒ_consumed(succ)) == ("-v",)
end

@testset "should parse long flag" begin
    parser = flag("--verbose")
    context = Context(buffer=["--verbose"], state=parser.initialState)

    result = splitparse(parser, context)

    @test !is_error(result)
    succ = unwrap(result)
    @test is_ok_and(==(true), ℒ_state(ℒ_nextctx(succ)))
    @test ctx_remaining(ℒ_nextctx(succ)) == String[]
    @test as_tuple(ℒ_consumed(succ)) == ("--verbose",)
end

@testset "should parse multiple flag names" begin
    parser = flag("-v", "--verbose")
    @test parse_ok(parser, ["-v"]) == true
    @test parse_ok(parser, ["--verbose"]) == true
end

@testset "should fail when flag is already set" begin
    parser = flag("-v")
    context = Context(buffer=["-v"], state=OptParse.ParseResult{Bool}(Ok(true)))

    result = splitparse(parser, context)

    @test is_error(result)
    fail = unwrap_error(result)
    @test ℒ_nconsumed(fail) == 1
    @test fail.error.domain == OptParse.ERR_ArgFlag
    @test OptParse.FlagErrCode(fail.error.code) == OptParse.FLAG_Duplicate
    @test fail.error.token == "-v"
end

#= bundled options are no longer responsibility of the flag parser =#
# @testset "should handle bundled short flags" begin
#     parser = flag("-v")
#     context = Context(buffer=["-vd", "ss"], state= parser.initialState)

#     result = splitparse(parser, context)

#     succ = unwrap(result)
#     @info ℒ_nextstate(succ)
#     @test is_ok_and(result) do succ
#         is_ok_and(==(true), ℒ_nextstate(succ))
#     end
#     succ = unwrap(result)
#     @test ctx_remaining(ℒ_nextctx(succ)) == ["-d", "ss"]
#     @test as_tuple(ℒ_consumed(succ)) == ("-v",)
# end

@testset "should fail when flags are terminated" begin
    parser = flag("-v")
    context = Context(buffer=["-v"], state=parser.initialState, optionsTerminated=true)

    result = splitparse(parser, context)

    @test is_error(result)
    fail = unwrap_error(result)
    @test ℒ_nconsumed(fail) == 0
    @test fail.error.domain == OptParse.ERR_ArgFlag
    @test OptParse.FlagErrCode(fail.error.code) == OptParse.FLAG_NoMoreOptions
end

@testset "should handle flags terminator --" begin
    parser = flag("-v")
    context = Context(buffer=["--"], state=parser.initialState)

    result = splitparse(parser, context)

    @test !is_error(result)
    succ = unwrap(result)
    @test (ℒ_optterm ∘ ℒ_nextctx)(succ) == true
    @test ctx_remaining(ℒ_nextctx(succ)) == String[]
    @test as_tuple(ℒ_consumed(succ)) == ("--",)
end

@testset "should handle option terminator edge cases correctly" begin
    @test_parse_error flag("-v") ["--", "-v"] OptParse.ERR_ArgFlag OptParse.FLAG_NoMoreOptions
    @test_parse_error flag("-v") ["--"] OptParse.ERR_ArgFlag OptParse.FLAG_Missing
    @test parse_ok(flag("-v"), ["-v", "--"]) == true
end

@testset "should handle empty buffer" begin
    parser = flag("-v")
    context = Context(buffer=String[], state=parser.initialState)

    result = splitparse(parser, context)

    @test is_error(result)
    fail = unwrap_error(result)
    @test ℒ_nconsumed(fail) == 0
    @test fail.error.domain == OptParse.ERR_ArgFlag
    @test OptParse.FlagErrCode(fail.error.code) == OptParse.FLAG_EndOfInput
end

@testset "should be type stable" begin
    @test_opt flag("-v")
    parser = flag("-v")

    @test_opt argparse(parser, ["-v"])
end
