@testset "should try parsers in order" begin
    parser1 = flag("-a")
    parser2 = flag("-b")
    orParser = or(parser1, parser2)

    using OptParse: OrState, FlagState, ParseSuccess
    # @test getproperty(orParser, :initialState) isa OrState{Union{Val{0}, Val{1}, Val{2}}, Tuple{Option{ParseSuccess{FlagState}}, Option{ParseSuccess{FlagState}}}}
    @test priority(orParser) == max(priority(parser1), priority(parser2))
end

@testset "should succeed with first matching parser" begin
    parser1 = flag("-a")
    parser2 = flag("-b")
    orParser = or(parser1, parser2)

    @test parse_ok(orParser, ["-a"]) == true
end

@testset "should succeed with second parser when first fails" begin
    parser1 = flag("-a")
    parser2 = flag("-b")
    orParser = or(parser1, parser2)

    @test parse_ok(orParser, ["-b"]) == true
end

@testset "should fail when no parser matches" begin
    parser1 = flag("-a")
    parser2 = flag("-b")
    orParser = or(parser1, parser2)

    err = parse_fail(orParser, ["-c"])
    @test err.domain == OptParse.ERR_ConstrOr
    @test OptParse.OrErrCode(err.code) == OptParse.OR_UnexpectedToken
end

@testset "should detect mutually exclusive options" begin
    parser1 = flag("-a")
    parser2 = flag("-b")
    orParser = or(parser1, parser2)

    err = parse_fail(orParser, ["-a", "-b"])
    @test err.domain == OptParse.ERR_ArgFlag
    @test OptParse.FlagErrCode(err.code) == OptParse.FLAG_NoMatch
end

@testset "should work with more than two parsers" begin
    parser1 = flag("-a")
    parser2 = flag("-b")
    parser3 = flag("-c")
    orParser = or(parser1, parser2, parser3)

    @test parse_ok(orParser, ["-a"]) == true

    @test parse_ok(orParser, ["-b"]) == true

    @test parse_ok(orParser, ["-c"]) == true
end

@testset "should allow duplicate option names in different branches" begin
    # or() allows duplicates because branches are mutually exclusive
    parser = or(
        flag("-v", "--verbose"),
        flag("-v", "--version"),
    )

    # Should succeed - first parser wins
    @test parse_ok(parser, ["-v"]) == true
end

@testset "should allow same options in nested or branches" begin
    parser = or(
        object((verbose = flag("-v"),)),
        object((version = flag("-v"),)),
        object((verify = flag("-v"),)),
    )

    # Should succeed - first matching branch wins
    @test parse_ok(parser, ["-v"]) == (; verbose = true)
end

@testset "Should handle control only matches correctly" begin
    parser = or(
        flag("-a"),
        argument(str()),
    )

    # A control-only success on `--` must not prevent later branches from
    # matching semantically.
    @test parse_ok(parser, ["--", "hello"]) == "hello"
    @test parse_ok(parser, ["--", "-a"]) == "-a"

    ctrlonly = or(
        flag("-a"),
        option("-b", str()),
    )

    # Bare `--` should not select a branch or create a conflict. Once option
    # parsing is terminated, the `or` should simply complete with no match.
    err = parse_fail(ctrlonly, ["--"])
    @test err.domain == OptParse.ERR_ConstrOr
    @test OptParse.OrErrCode(err.code) == OptParse.OR_NoMatch
end

@testset "should treat everything after -- as positional input rather than command syntax" begin
    parser = or(
        command("test", object((opt = option("-v", integer()),))),
        argument(str()),
    )

    @test parse_ok(parser, ["--", "test"]) == "test"
    @test parse_ok(parser, ["--", "-v"]) == "-v"
end

@testset "should keep parsing the already selected branch after command match" begin
    parser = or(
        command("bye", object((
            name = option("-n", str()),
            port = option("-p", integer()),
        ))),
        multiple(argument(str())),
    )

    # Once `bye` has selected the command branch, later tokens must stay inside
    # that branch. They must not reactivate the positional fallback branch.
    err = parse_fail(parser, ["bye", "--", "-n"])
    @test err.domain == OptParse.ERR_ConstrObject
end

@testset "should append a single breadcrumb when an alternative branch is selected" begin
    parser = or(
        flag("-a"),
        flag("-b"),
    )

    ctx = Context(buffer=["-b"], state=parser.initialState)
    pres = splitparse(parser, ctx)
    @test !is_error(pres)

    succ = unwrap(pres)
    @test ℒ_path(ℒ_nextctx(succ)) == [usage_alternative_branch(2)]
end

@testset "should not duplicate alternative breadcrumbs after branch selection" begin
    parser = or(
        command("bye", object((
            name = option("-n", str()),
            port = option("-p", integer()),
        ))),
        multiple(argument(str())),
    )

    ctx1 = Context(buffer=["bye", "-n", "alice"], state=parser.initialState)
    pres1 = splitparse(parser, ctx1)
    @test !is_error(pres1)
    succ1 = unwrap(pres1)
    @test ℒ_path(ℒ_nextctx(succ1)) == [usage_alternative_branch(1)]

    ctx2 = Context(
        buffer=["-p", "8080"],
        state=ℒ_state(ℒ_nextctx(succ1)),
        path=ℒ_path(ℒ_nextctx(succ1)),
    )
    pres2 = splitparse(parser, ctx2)
    @test !is_error(pres2)
    succ2 = unwrap(pres2)
    @test ℒ_path(ℒ_nextctx(succ2)) == [usage_alternative_branch(1)]
end

@testset "should be type stable" begin
    @test_opt or(
        object((verbose = flag("-v"),)),
        object((version = flag("-v"),)),
        object((verify = flag("-v"),)),
    )

    parser = or(
        object((verbose = flag("-v"),)),
        object((version = flag("-v"),)),
        object((verify = flag("-v"),)),
    )

    @test_opt argparse(parser, ["-v"])
end
