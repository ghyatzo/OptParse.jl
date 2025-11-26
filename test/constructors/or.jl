@testset "should try parsers in order" begin
    parser1 = flag("-a")
    parser2 = flag("-b")
    orParser = or(parser1, parser2)

    using ComposableCLIParse: OrState, FlagState, ParseSuccess
    @test getproperty(orParser, :initialState) isa OrState{Union{Val{0}, Val{1}, Val{2}}, Tuple{Option{ParseSuccess{FlagState}}, Option{ParseSuccess{FlagState}}}}
    @test priority(orParser) == max(priority(parser1), priority(parser2))
end

@testset "should succeed with first matching parser" begin
    parser1 = flag("-a")
    parser2 = flag("-b")
    orParser = or(parser1, parser2)

    res = argparse(orParser, ["-a"])
    @test is_ok_and(==(true), res)
end

@testset "should succeed with second parser when first fails" begin
    parser1 = flag("-a")
    parser2 = flag("-b")
    orParser = or(parser1, parser2)

    res = argparse(orParser, ["-b"])
    @test is_ok_and(==(true), res)
end

@testset "should fail when no parser matches" begin
    parser1 = flag("-a")
    parser2 = flag("-b")
    orParser = or(parser1, parser2)

    res = argparse(orParser, ["-c"])
    @test is_error(res)
    err = unwrap_error(res)
    @test occursin("Unexpected option or subcommand", string(err))
end

@testset "should detect mutually exclusive options" begin
    parser1 = flag("-a")
    parser2 = flag("-b")
    orParser = or(parser1, parser2)

    res = argparse(orParser, ["-a", "-b"])
    @test is_error(res)
    err = unwrap_error(res)
    @test occursin("can't be used together", string(err))
end

@testset "should work with more than two parsers" begin
    parser1 = flag("-a")
    parser2 = flag("-b")
    parser3 = flag("-c")
    orParser = or(parser1, parser2, parser3)

    resultA = argparse(orParser, ["-a"])
    @test is_ok_and(==(true), resultA)

    resultB = argparse(orParser, ["-b"])
    @test is_ok_and(==(true), resultB)

    resultC = argparse(orParser, ["-c"])
    @test is_ok_and(==(true), resultC)
end

@testset "should allow duplicate option names in different branches" begin
    # or() allows duplicates because branches are mutually exclusive
    parser = or(
        flag("-v", "--verbose"),
        flag("-v", "--version"),
    )

    res = argparse(parser, ["-v"])
    @test is_ok_and(==(true), res)  # Should succeed - first parser wins
end

@testset "should allow same options in nested or branches" begin
    parser = or(
        object((verbose = flag("-v"),)),
        object((version = flag("-v"),)),
        object((verify = flag("-v"),)),
    )

    res = argparse(parser, ["-v"])
    @test is_ok_and(res) do val
        # Should succeed - first matching branch wins
        val == (; verbose = true)
    end
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
