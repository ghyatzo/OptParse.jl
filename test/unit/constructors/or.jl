@testset "should try parsers in order" begin
    parser1 = switch("-a")
    parser2 = switch("-b")
    orParser = or(parser1, parser2)

    @test priority(orParser) == max(priority(parser1), priority(parser2))
end

@testset "should succeed with first matching parser" begin
    parser1 = switch("-a")
    parser2 = switch("-b")
    orParser = or(parser1, parser2)

    @test parse_ok(orParser, ["-a"]) == true
end

@testset "should succeed with second parser when first fails" begin
    parser1 = switch("-a")
    parser2 = switch("-b")
    orParser = or(parser1, parser2)

    @test parse_ok(orParser, ["-b"]) == true
end

@testset "should fail when no parser matches" begin
    parser1 = switch("-a")
    parser2 = switch("-b")
    orParser = or(parser1, parser2)

    err = parse_fail(orParser, ["-c"])
    @test err isa OptParse.ConstrOrError
    @test err.code == OptParse.OR_UnexpectedToken
end

@testset "should detect mutually exclusive options" begin
    parser1 = switch("-a")
    parser2 = switch("-b")
    orParser = or(parser1, parser2)

    err = parse_fail(orParser, ["-a", "-b"])
    @test err isa OptParse.ArgGateError
    @test err.code == OptParse.GATE_NoMatch
end

@testset "should work with more than two parsers" begin
    parser1 = switch("-a")
    parser2 = switch("-b")
    parser3 = switch("-c")
    orParser = or(parser1, parser2, parser3)

    @test parse_ok(orParser, ["-a"]) == true

    @test parse_ok(orParser, ["-b"]) == true

    @test parse_ok(orParser, ["-c"]) == true
end

@testset "should allow duplicate option names in different branches" begin
    # or() allows duplicates because branches are mutually exclusive
    parser = or(
        switch("-v", "--verbose"),
        switch("-v", "--version"),
    )

    # Should succeed - first parser wins
    @test parse_ok(parser, ["-v"]) == true
end

@testset "should allow same options in nested or branches" begin
    parser = or(
        record(; verbose = switch("-v")),
        record(; version = switch("-v")),
        record(; verify = switch("-v")),
    )

    # Should succeed - first matching branch wins
    @test parse_ok(parser, ["-v"]) == (; verbose = true)
end

@testset "Should handle control only matches correctly" begin
    parser = or(
        switch("-a"),
        arg(str()),
    )

    # A control-only success on `--` must not prevent later branches from
    # matching semantically.
    @test parse_ok(parser, ["--", "hello"]) == "hello"
    @test parse_ok(parser, ["--", "-a"]) == "-a"

    ctrlonly = or(
        switch("-a"),
        option("-b", str()),
    )

    # Bare `--` should not select a branch or create a conflict. Once option
    # parsing is terminated, the `or` should simply complete with no match.
    err = parse_fail(ctrlonly, ["--"])
    @test err isa OptParse.ConstrOrError
    @test err.code == OptParse.OR_NoMatch
end

@testset "should treat everything after -- as positional input rather than command syntax" begin
    parser = or(
        command("test", record(; opt = option("-v", integer()))),
        arg(str()),
    )

    @test parse_ok(parser, ["--", "test"]) == "test"
    @test parse_ok(parser, ["--", "-v"]) == "-v"
end

@testset "should keep parsing the already selected branch after command match" begin
    parser = or(
        command("bye", record(;
            name = option("-n", str()),
            port = option("-p", integer()),
        )),
        many(arg(str())),
    )

    # Once `bye` has selected the command branch, later tokens must stay inside
    # that branch. They must not reactivate the positional fallback branch.
    err = parse_fail(parser, ["bye", "--", "-n"])
    @test err isa OptParse.ConstrObjectError
end

@testset "should keep parsing selected alternative state after branch selection" begin
    parser = or(
        command("bye", record(;
            name = option("-n", str()),
            port = option("-p", integer()),
        )),
        many(arg(str())),
    )

    ctx1 = mkctx(["bye", "-n", "alice"], parser.initialState)
    pres1 = splitparse(parser, ctx1)
    @test !is_error(pres1)
    succ1 = unwrap(pres1)

    ctx2 = mkctx(["-p", "8080"], state(res_nextctx(succ1)))
    pres2 = splitparse(parser, ctx2)
    @test !is_error(pres2)
end

@testset "should expose named branch selections" begin
    parser = or(option("--number", integer()), option("--name", str()))
    @test parser.initialState == state_t(parser)'.NotMatched
    result = splitcomplete(parser, parser.initialState)
    @test is_error(result)
    @test unwrap_error(result).code == OptParse.OR_NoMatch

    for (i, buffer, value) in ((1, ["--number", "42"], 42), (2, ["--name", "alice"], "alice"))
        result = splitparse(parser, mkctx(buffer, parser.initialState))
        @test !is_error(result)
        st = res_nextstate(unwrap(result))
        selected = OptParse.@cases st begin
            NotMatched => error("Expected a selected branch")
            Selected(branch) => unwrapunion(branch)
        end
        @test OptParse.branch_idx(typeof(selected)) == i
        @test unwrap(splitcomplete(parser, st)) == value
    end
end

@testset "should defer selected child value errors" begin
    parser = or(option("--number", integer()), arg(str()))
    result = splitparse(parser, mkctx(["--number", "invalid"], parser.initialState))
    @test !is_error(result)
    st = res_nextstate(unwrap(result))
    result = splitcomplete(parser, st)
    @test is_error(result)
    @test unwrap_error(result).code == OptParse.INTEGER_Invalid
end

@testset "should preserve selection through control-only matches" begin
    parser = or(option("--number", integer()), arg(str()))
    result = splitparse(parser, mkctx(["--"], parser.initialState))
    @test !is_error(result)
    @test res_nextstate(unwrap(result)) == parser.initialState
    @test options_terminated(res_nextctx(unwrap(result)))
    @test !OptParse.res_matchcounts(unwrap(result))

    result = splitparse(parser, mkctx(["--number", "42"], parser.initialState))
    @test !is_error(result)
    st = res_nextstate(unwrap(result))
    result = splitparse(parser, mkctx(["--"], st))
    @test !is_error(result)
    ps = unwrap(result)
    @test options_terminated(res_nextctx(ps))
    @test !OptParse.res_matchcounts(ps)
    @test unwrap(splitcomplete(parser, res_nextstate(ps))) == 42
end

@testset "should focus help on the selected branch" begin
    parser = or(command("add", arg(str("FILE"))), command("remove", arg(str("TARGET"))))
    @test length(OptParse.build_help_doc(parser, String[]).entries) == 2
    doc = OptParse.build_help_doc(parser, ["remove"])
    @test doc.prefix == ["remove"]
    @test occursin("TARGET", OptParse.render_usage(doc.usage))
    @test !occursin("FILE", OptParse.render_usage(doc.usage))
end

@testset "should be type stable" begin
    @test_opt or(
        record(; verbose = switch("-v")),
        record(; version = switch("-v")),
        record(; verify = switch("-v")),
    )

end
