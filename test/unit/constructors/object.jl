@testset "should combine multiple parsers into an object" begin
    parser = object(
        (
            verbose = gate("-v", "--verbose"),
            port = option(("-p", "--port"), integer()),
        )
    )

    @test priority(parser) >= 10

    # initialState should contain fields :verbose and :port
    names = propertynames(parser.initialState)
    @test :verbose in names
    @test :port in names
end

@testset "should parse multiple options in sequence" begin
    parser = object(
        (
            verbose = gate("-v"),
            port = option("-p", integer()),
        )
    )

    argv = ["-v", "-p", "8080"]
    ctx = mkctx(argv, parser.initialState)
    res = splitparse(parser, ctx)

    @test !is_error(res)
    ps = unwrap(res)
    st = res_nextstate(ps)
    @test haskey(Dict(propertynames(st) .=> getfield.(Ref(st), propertynames(st))), :verbose)
    @test haskey(Dict(propertynames(st) .=> getfield.(Ref(st), propertynames(st))), :port)
    @test (@? getfield(st, :verbose)) == true
    @test (@? getfield(st, :port)) == 8080
end

@testset "should work with labeled objects" begin
    parser = object(
        "Test Group", (
            flag = gate("-f"),
        )
    )

    names = propertynames(parser.initialState)
    @test :flag in names
end

@testset "should handle parsing failure in nested parser" begin
    parser = object(
        (
            port = option("-p", integer(; min = 1)),
        )
    )

    err = parse_fail(parser, ["-p", "0"])
    @test err.domain == OptParse.ERR_IntegerVal
end

@testset "should fail when no option matches" begin
    parser = object(
        (
            verbose = gate("-v"),
        )
    )

    buffer = ["--help"]
    state = parser.initialState
    # optionsTerminated defaults to false
    ctx = mkctx(buffer, state)
    res = splitparse(parser, ctx)

    @test is_error(res)
    pf = unwrap_error(res)
    @test pf.consumed == 0
    @test pf.error.domain == OptParse.ERR_ConstrObject
    @test OptParse.ObjectErrCode(pf.error.code) == OptParse.OBJECT_UnexpectedToken
end

@testset "should handle empty arguments gracefully when required options are present" begin
    parser = object(
        (
            verbose = gate("-v"),
            port = option("-p", integer()),
        )
    )

    argv = String[]
    ctx = mkctx(argv, parser.initialState)
    res = splitparse(parser, ctx)

    @test is_error(res)
    pf = unwrap_error(res)
    @test pf.error.domain == OptParse.ERR_ConstrObject
    @test OptParse.ObjectErrCode(pf.error.code) == OptParse.OBJECT_EndOfInput
end

@testset "handles complex objects" begin

    obj = object(
        "test", (
            cst = @constant(10),
            option = option("--host", str(; metavar = "HOST")),
            flag = gate("--verbose", "-v"),
            flag2 = gate("--test"),
            arg = arg(str(; metavar = "TEST")),
        )
    )

    ctx = mkctx(["--verbose", "--host", "me", "--test", "--", "--test"], obj.initialState)

    result = splitparse(obj, ctx)
    @test !is_error(result)
    succ = unwrap(result)

    st = res_nextstate(succ)
    comp = splitcomplete(obj, st)

    @test !is_error(comp)
    succ = unwrap(comp)

    @test succ.cst == Val(10)
    @test succ.option == "me"
    @test succ.flag == true
    @test succ.flag2 == true
    @test succ.arg == "--test"
end

@testset "should handle -- edge cases" begin
    obj = object(
        "test", (
            option = option("--host", str(; metavar = "HOST")),
            flag = optional(gate("--verbose", "-v")),
            arg = arg(str(; metavar = "TEST")),
        )
    )

    @test parse_ok(obj, ["--host", "host", "--", "ARG"]) == (option = "host", flag = nothing, arg = "ARG")

    err = parse_fail(obj, ["ARG", "--host", "host", "--", "-v"])
    # the "-v" is correctly interpreted not as an option but as an argument.
    # in this case the object will fail to match any of its inner parsers, raising a NoProgress error
    @test err.domain == OptParse.ERR_Main

    @test parse_ok(obj, ["--host", "host", "ARG", "--"]) == (option = "host", flag = nothing, arg = "ARG")

end

@testset "should be type stable" begin

    @test_opt object(
        "test", (
            cst = @constant(10),
            option = option("--host", str(; metavar = "HOST")),
            flag = gate("--verbose", "-v"),
            flag2 = gate("--test"),
            arg = arg(str(; metavar = "TEST")),
        )
    )

    obj = object(
        "test", (
            cst = @constant(10),
            option = option("--host", str(; metavar = "HOST")),
            flag = gate("--verbose", "-v"),
            flag2 = gate("--test"),
            arg = arg(str(; metavar = "TEST")),
        )
    )

    ctx = mkctx(["--verbose", "--host", "me", "--test", "--", "--test"], obj.initialState)

    @test_opt parse(unwrapunion(obj), ctx)

    res = splitparse(obj, ctx)
    succ = unwrap(res)

    @test_opt complete(unwrapunion(obj), res_nextstate(succ))
end
