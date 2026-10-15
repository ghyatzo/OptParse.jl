@testset "should combine multiple parsers into an record" begin
    parser = record(
        (
            verbose = switch("-v", "--verbose"),
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
    parser = record(
        (
            verbose = switch("-v"),
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
    @test getfield(st, :verbose) == OptParse.GateState'.Matched
    @test getfield(st, :port) == OptParse.OptionState{Int, OptParse.IntegerValError}'.Matched(8080)
end

@testset "should work with labeled records" begin
    parser = record(
        "Test Group", (
            flag = switch("-f"),
        )
    )

    names = propertynames(parser.initialState)
    @test :flag in names
end

@testset "should handle parsing failure in nested parser" begin
    parser = record(
        (
            port = option("-p", integer(; min = 1)),
        )
    )

    err = parse_fail(parser, ["-p", "0"])
    @test err isa OptParse.IntegerValError
end

@testset "should fail when no option matches" begin
    parser = record(
        (
            verbose = switch("-v"),
        )
    )

    buffer = ["--help"]
    istate = parser.initialState
    # optionsTerminated defaults to false
    ctx = mkctx(buffer, istate)
    res = splitparse(parser, ctx)

    @test is_error(res)
    pf = unwrap_error(res)
    @test pf.consumed == 0
    @test pf.error isa OptParse.ConstrObjectError
    @test pf.error.code == OptParse.OBJECT_UnexpectedToken
end

@testset "should handle empty arguments gracefully when required options are present" begin
    parser = record(
        (
            verbose = switch("-v"),
            port = option("-p", integer()),
        )
    )

    argv = String[]
    ctx = mkctx(argv, parser.initialState)
    res = splitparse(parser, ctx)

    @test is_error(res)
    pf = unwrap_error(res)
    @test pf.error isa OptParse.ConstrObjectError
    @test pf.error.code == OptParse.OBJECT_EndOfInput
end

@testset "handles complex records" begin

    obj = record(
        "test", (
            cst = @constant(10),
            option = option("--host", str(; metavar = "HOST")),
            flag = switch("--verbose", "-v"),
            flag2 = switch("--test"),
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
    obj = record(
        "test", (
            option = option("--host", str(; metavar = "HOST")),
            flag = optional(switch("--verbose", "-v")),
            arg = arg(str(; metavar = "TEST")),
        )
    )

    @test parse_ok(obj, ["--host", "host", "--", "ARG"]) == (option = "host", flag = nothing, arg = "ARG")

    err = parse_fail(obj, ["TEST", "--host", "host", "--", "-v"])
    # the "-v" is correctly interpreted not as an option but as an argument.
    # The positional argument is already matched, so "-v" is unexpected.
    @test err isa OptParse.ConstrObjectError
    @test err.code == OptParse.OBJECT_UnexpectedToken

    @test parse_ok(obj, ["--host", "host", "ARG", "--"]) == (option = "host", flag = nothing, arg = "ARG")

end

@testset "should report unexpected tokens on extra positional arguments (#17)" begin
    parser = record(
        a = arg(str("A")),
        b = arg(str("B")),
    )

    err = parse_fail(parser, ["x", "y", "z"])
    @test err isa OptParse.ConstrObjectError
    @test err.code == OptParse.OBJECT_UnexpectedToken
    @test string(err) == "Unexpected option or argument: z"

    # Child errors with consumed tokens take precedence over unexpected tokens.
    parser_opt = record(
        h = default(option("--host", str("HOST")), "localhost"),
    )
    err_unknown = parse_fail(parser_opt, ["--hots", "example.org"])
    @test err_unknown isa OptParse.ConstrObjectError
    @test err_unknown.code == OptParse.OBJECT_UnexpectedToken
    @test string(err_unknown) == "Unexpected option or argument: --hots"

    err_dup = parse_fail(parser_opt, ["--host", "a", "--host", "b"])
    @test err_dup isa OptParse.ArgOptionError
    @test err_dup.code == OptParse.OPTION_Duplicate

    err_missing_val = parse_fail(parser_opt, ["--host"])
    @test err_missing_val isa OptParse.ArgOptionError
    @test err_missing_val.code == OptParse.OPTION_MissingValue
end

@testset "should handle empty input if all optional (#9)" begin
    parser = record(
        verbose = flag("-v", "--verbose"),
        files = many(arg(str("FILE")))
    )

    @test parse_ok(parser, String[]) == (verbose = false, files = String[])
end
