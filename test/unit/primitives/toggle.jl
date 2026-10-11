@testset "should error with short or malformed positive names" begin
    @test_throws ArgumentError toggle("-t")
    @test_throws ArgumentError toggle("tags")
    @test_throws ArgumentError toggle("---tags")
    @test_throws ArgumentError toggle("--no-tags")
end

@testset "should derive the negative spelling and compact usage" begin
    inner = OptParse.ArgToggle("--tags")
    @test inner.positive == "--tags"
    @test inner.negative == "--no-tags"
    @test OptParse.usage(inner).names == ["--[no-]tags"]
end

@testset "should complete toggle states" begin
    inner = OptParse.ArgToggle("--tags")
    @test inner.initialState == OptParse.ToggleState'.NotMatched
    @test is_ok_and(==(true), splitcomplete(inner, OptParse.ToggleState'.Matched(true)))
    @test is_ok_and(==(false), splitcomplete(inner, OptParse.ToggleState'.Matched(false)))

    result = splitcomplete(inner, inner.initialState)
    @test is_error(result)
    err = unwrap_error(result)
    @test err.code == OptParse.TOGGLE_Missing
    @test sprint(OptParse.render_error, err) ==
        "Missing required flag(s): $(OptParse._names_detail([inner.positive, inner.negative]))"
end

@testset "should return nothing, true, or false" begin
    @test parse_ok(toggle("--tags"), String[]) === nothing
    @test parse_ok(toggle("--tags"), ["--tags"]) === true
    @test parse_ok(toggle("--tags"), ["--no-tags"]) === false
end

@testset "should parse positive spelling" begin
    inner = OptParse.ArgToggle("--tags")
    context = mkctx(["--tags"], inner.initialState)

    result = splitparse(inner, context)

    @test !is_error(result)
    succ = unwrap(result)
    @test state(res_nextctx(succ)) == OptParse.ToggleState'.Matched(true)
    @test remaining(res_nextctx(succ)) == String[]
    @test as_tuple(res_consumed(succ)) == ("--tags",)
end

@testset "should parse negative spelling" begin
    inner = OptParse.ArgToggle("--tags")
    context = mkctx(["--no-tags"], inner.initialState)

    result = splitparse(inner, context)

    @test !is_error(result)
    succ = unwrap(result)
    @test state(res_nextctx(succ)) == OptParse.ToggleState'.Matched(false)
    @test remaining(res_nextctx(succ)) == String[]
    @test as_tuple(res_consumed(succ)) == ("--no-tags",)
end

@testset "should fail when the same spelling is repeated" begin
    inner = OptParse.ArgToggle("--tags")
    context = mkctx(["--tags"], OptParse.ToggleState'.Matched(true))

    result = splitparse(inner, context)

    @test is_error(result)
    fail = unwrap_error(result)
    @test res_num_consumed(fail) == 1
    @test fail.error isa OptParse.ArgToggleError
    @test fail.error.code == OptParse.TOGGLE_Duplicate
    @test fail.error.token == "--tags"
end

@testset "should fail when both spellings are present" begin
    inner = OptParse.ArgToggle("--tags")
    context = mkctx(["--no-tags"], OptParse.ToggleState'.Matched(true))

    result = splitparse(inner, context)

    @test is_error(result)
    fail = unwrap_error(result)
    @test res_num_consumed(fail) == 1
    @test fail.error.code == OptParse.TOGGLE_Conflict
    @test fail.error.token == "--no-tags"
    @test fail.error.detail == "--tags"
end

@testset "should fail when flags are terminated" begin
    inner = OptParse.ArgToggle("--tags")
    context = mkctx(["--tags"], inner.initialState; options_terminated = true)

    result = splitparse(inner, context)

    @test is_error(result)
    fail = unwrap_error(result)
    @test res_num_consumed(fail) == 0
    @test fail.error.code == OptParse.TOGGLE_NoMoreOptions
end

@testset "should handle flags terminator --" begin
    inner = OptParse.ArgToggle("--tags")
    context = mkctx(["--"], inner.initialState)

    result = splitparse(inner, context)

    @test !is_error(result)
    succ = unwrap(result)
    @test options_terminated(res_nextctx(succ)) == true
    @test state(res_nextctx(succ)) == OptParse.ToggleState'.NotMatched
    @test remaining(res_nextctx(succ)) == String[]
    @test as_tuple(res_consumed(succ)) == ("--",)
end

@testset "should handle empty buffer" begin
    inner = OptParse.ArgToggle("--tags")
    context = mkctx(String[], inner.initialState)

    result = splitparse(inner, context)

    @test is_error(result)
    fail = unwrap_error(result)
    @test res_num_consumed(fail) == 0
    @test fail.error.code == OptParse.TOGGLE_EndOfInput
end

@testset "should default to nothing inside records" begin
    parser = record((tags = toggle("--tags"),))
    @test parse_ok(parser, String[]) == (tags = nothing,)
    @test parse_ok(parser, ["--tags"]) == (tags = true,)
    @test parse_ok(parser, ["--no-tags"]) == (tags = false,)
end

@testset "should surface strict duplicate and conflict errors" begin
    @test_parse_error toggle("--tags") ["--tags", "--tags"] OptParse.ArgToggleError OptParse.TOGGLE_Duplicate
    @test_parse_error toggle("--tags") ["--tags", "--no-tags"] OptParse.ArgToggleError OptParse.TOGGLE_Conflict
    @test_parse_error toggle("--tags") ["--no-tags", "--tags"] OptParse.ArgToggleError OptParse.TOGGLE_Conflict
end

@testset "should handle option terminator edge cases correctly" begin
    @test parse_ok(toggle("--tags"), ["--"]) === nothing
    @test_parse_error toggle("--tags") ["--", "--tags"] OptParse.MainError OptParse.MAIN_UnexpectedToken
end

@testset "should be type stable" begin
    @test_opt toggle("--tags")
    parser = toggle("--tags")

    @test_opt optparse(parser, ["--tags"])
end
