@testset "should error with short flags longer than 1 character" begin
    @test_throws ArgumentError switch("-invalid")
end


@testset "should error with flags not starting with - or --" begin
    @test_throws ArgumentError switch("aaa")
    @test_throws ArgumentError switch("?aaa")
    @test_throws ArgumentError switch("/aaa")
    @test_throws ArgumentError switch("---aaa")
end

@testset "should parse single short switch" begin
    parser = switch("-v")
    context = mkctx(["-v"], parser.initialState)

    result = splitparse(parser, context)

    @test !is_error(result)
    succ = unwrap(result)
    @test is_ok_and(==(true), ctx_state(res_nextctx(succ)))
    @test ctx_remaining(res_nextctx(succ)) == String[]
    @test as_tuple(res_consumed(succ)) == ("-v",)
end

@testset "should parse long switch" begin
    parser = switch("--verbose")
    context = mkctx(["--verbose"], parser.initialState)

    result = splitparse(parser, context)

    @test !is_error(result)
    succ = unwrap(result)
    @test is_ok_and(==(true), ctx_state(res_nextctx(succ)))
    @test ctx_remaining(res_nextctx(succ)) == String[]
    @test as_tuple(res_consumed(succ)) == ("--verbose",)
end

@testset "should parse multiple switch names" begin
    parser = switch("-v", "--verbose")
    @test parse_ok(parser, ["-v"]) == true
    @test parse_ok(parser, ["--verbose"]) == true
end

@testset "should fail when switch is already set" begin
    parser = switch("-v")
    context = mkctx(["-v"], OptParse.ParseResult{Bool}(Ok(true)))

    result = splitparse(parser, context)

    @test is_error(result)
    fail = unwrap_error(result)
    @test res_num_consumed(fail) == 1
    @test fail.error.domain == OptParse.ERR_ArgGate
    @test OptParse.GateErrCode(fail.error.code) == OptParse.GATE_Duplicate
    @test fail.error.token == "-v"
end

#= bundled options are no longer responsibility of the switch parser =#
# @testset "should handle bundled short flags" begin
#     parser = switch("-v")
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
    parser = switch("-v")
    context = mkctx(["-v"], parser.initialState; options_terminated=true)

    result = splitparse(parser, context)

    @test is_error(result)
    fail = unwrap_error(result)
    @test res_num_consumed(fail) == 0
    @test fail.error.domain == OptParse.ERR_ArgGate
    @test OptParse.GateErrCode(fail.error.code) == OptParse.GATE_NoMoreOptions
end

@testset "should handle flags terminator --" begin
    parser = switch("-v")
    context = mkctx(["--"], parser.initialState)

    result = splitparse(parser, context)

    @test !is_error(result)
    succ = unwrap(result)
    @test ctx_optterm(res_nextctx(succ)) == true
    @test ctx_remaining(res_nextctx(succ)) == String[]
    @test as_tuple(res_consumed(succ)) == ("--",)
end

@testset "should handle option terminator edge cases correctly" begin
    @test_parse_error switch("-v") ["--", "-v"] OptParse.ERR_ArgGate OptParse.GATE_NoMoreOptions
    @test_parse_error switch("-v") ["--"] OptParse.ERR_ArgGate OptParse.GATE_Missing
    @test parse_ok(switch("-v"), ["-v", "--"]) == true
end

@testset "should handle empty buffer" begin
    parser = switch("-v")
    context = mkctx(String[], parser.initialState)

    result = splitparse(parser, context)

    @test is_error(result)
    fail = unwrap_error(result)
    @test res_num_consumed(fail) == 0
    @test fail.error.domain == OptParse.ERR_ArgGate
    @test OptParse.GateErrCode(fail.error.code) == OptParse.GATE_EndOfInput
end

@testset "should be type stable" begin
    @test_opt switch("-v")
    parser = switch("-v")

    @test_opt optparse(parser, ["-v"])
end
