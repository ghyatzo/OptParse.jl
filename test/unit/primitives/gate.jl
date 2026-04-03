@testset "should error with short flags longer than 1 character" begin
    @test_throws ArgumentError gate("-invalid")
end


@testset "should error with flags not starting with - or --" begin
    @test_throws ArgumentError gate("aaa")
    @test_throws ArgumentError gate("?aaa")
    @test_throws ArgumentError gate("/aaa")
    @test_throws ArgumentError gate("---aaa")
end

@testset "should parse single short gate" begin
    parser = gate("-v")
    context = Context(buffer=["-v"], state=parser.initialState)

    result = splitparse(parser, context)

    @test !is_error(result)
    succ = unwrap(result)
    @test is_ok_and(==(true), ℒ_state(ℒ_nextctx(succ)))
    @test ctx_remaining(ℒ_nextctx(succ)) == String[]
    @test as_tuple(ℒ_consumed(succ)) == ("-v",)
end

@testset "should parse long gate" begin
    parser = gate("--verbose")
    context = Context(buffer=["--verbose"], state=parser.initialState)

    result = splitparse(parser, context)

    @test !is_error(result)
    succ = unwrap(result)
    @test is_ok_and(==(true), ℒ_state(ℒ_nextctx(succ)))
    @test ctx_remaining(ℒ_nextctx(succ)) == String[]
    @test as_tuple(ℒ_consumed(succ)) == ("--verbose",)
end

@testset "should parse multiple gate names" begin
    parser = gate("-v", "--verbose")
    @test parse_ok(parser, ["-v"]) == true
    @test parse_ok(parser, ["--verbose"]) == true
end

@testset "should fail when gate is already set" begin
    parser = gate("-v")
    context = Context(buffer=["-v"], state=OptParse.ParseResult{Bool}(Ok(true)))

    result = splitparse(parser, context)

    @test is_error(result)
    fail = unwrap_error(result)
    @test ℒ_nconsumed(fail) == 1
    @test fail.error.domain == OptParse.ERR_ArgGate
    @test OptParse.GateErrCode(fail.error.code) == OptParse.GATE_Duplicate
    @test fail.error.token == "-v"
end

#= bundled options are no longer responsibility of the gate parser =#
# @testset "should handle bundled short flags" begin
#     parser = gate("-v")
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
    parser = gate("-v")
    context = Context(buffer=["-v"], state=parser.initialState, optionsTerminated=true)

    result = splitparse(parser, context)

    @test is_error(result)
    fail = unwrap_error(result)
    @test ℒ_nconsumed(fail) == 0
    @test fail.error.domain == OptParse.ERR_ArgGate
    @test OptParse.GateErrCode(fail.error.code) == OptParse.GATE_NoMoreOptions
end

@testset "should handle flags terminator --" begin
    parser = gate("-v")
    context = Context(buffer=["--"], state=parser.initialState)

    result = splitparse(parser, context)

    @test !is_error(result)
    succ = unwrap(result)
    @test (ℒ_optterm ∘ ℒ_nextctx)(succ) == true
    @test ctx_remaining(ℒ_nextctx(succ)) == String[]
    @test as_tuple(ℒ_consumed(succ)) == ("--",)
end

@testset "should handle option terminator edge cases correctly" begin
    @test_parse_error gate("-v") ["--", "-v"] OptParse.ERR_ArgGate OptParse.GATE_NoMoreOptions
    @test_parse_error gate("-v") ["--"] OptParse.ERR_ArgGate OptParse.GATE_Missing
    @test parse_ok(gate("-v"), ["-v", "--"]) == true
end

@testset "should handle empty buffer" begin
    parser = gate("-v")
    context = Context(buffer=String[], state=parser.initialState)

    result = splitparse(parser, context)

    @test is_error(result)
    fail = unwrap_error(result)
    @test ℒ_nconsumed(fail) == 0
    @test fail.error.domain == OptParse.ERR_ArgGate
    @test OptParse.GateErrCode(fail.error.code) == OptParse.GATE_EndOfInput
end

@testset "should be type stable" begin
    @test_opt gate("-v")
    parser = gate("-v")

    @test_opt argparse(parser, ["-v"])
end
