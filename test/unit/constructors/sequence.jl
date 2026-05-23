@testset "should create a parser with array-based API" begin
    parser = sequence(
        switch("-v", "--verbose"),
        option(("-p", "--port"), integer()),
    )

    @test priority(parser) >= 10
    init = getproperty(parser, :initialState)
    @test init isa Tuple
    @test length(init) == 2
end

@testset "should parse parsers sequentially in array order" begin
    parser = sequence(
        option(("-n", "--name"), str()),
        switch("-v", "--verbose"),
    )

    val = parse_ok(parser, ["-n", "Alice", "-v"])
    @test val == ("Alice", true)
end

@testset "should work with labeled sequences" begin
    parser = sequence("User Data",
        option(("-n", "--name"), str()),
        switch("-v", "--verbose"),
    )

    val = parse_ok(parser, ["-n", "Bob", "-v"])
    @test val == ("Bob", true)
end

@testset "should handle empty sequence" begin
    parser = sequence()  # empty sequence of parsers

    val = parse_ok(parser, String[])
    @test length(val) == 0
end

@testset "should work with optional parsers" begin
    parser = sequence(
        option(("-n", "--name"), str()),
        optional(option(("-a", "--age"), integer())),
        switch("-v", "--verbose"),
    )

    val1 = parse_ok(parser, ["-n", "Alice", "-a", "30", "-v"])
    @test val1 == ("Alice", 30, true)

    val2 = parse_ok(parser, ["-n", "Bob", "-v"])
    @test val2 == ("Bob", nothing, true)
end

@testset "should work with arguments first, then options" begin
    parser = sequence(
        arg(str()),
        switch("-v", "--verbose"),
        option(("-o", "--output"), str()),
    )

    val = parse_ok(parser, ["input.txt", "-v", "-o", "output.txt"])
    @test val == ("input.txt", true, "output.txt")
end

@testset "should work with multiple arguments and options mixed" begin
    parser = sequence(
        arg(str()),
        arg(str()),
        switch("-v", "--verbose"),
    )

    val = parse_ok(parser, ["file1.txt", "file2.txt", "-v"])
    @test val == ("file1.txt", "file2.txt", true)
end

@testset "should handle argument-option-argument pattern" begin
    parser = sequence(
        arg(str()),
        option(("-t", "--type"), str()),
        arg(str()),
    )

    val = parse_ok(parser, ["input.txt", "-t", "json", "output.txt"])
    @test val == ("input.txt", "json", "output.txt")
end

@testset "should fail when argument parser cannot find expected argument" begin
    parser = sequence(
        arg(str()),
        switch("-v", "--verbose"),
    )

    # No arguments provided, should fail on first argument parser
    @test is_error(tryoptparse(parser, ["-v"]))
end

@testset "should work with complex argument and option combinations" begin
    # CLI pattern: command input_file --format json --verbose output_file
    parser = sequence(
        arg(str(; metavar = "COMMAND")),
        arg(str(; metavar = "INPUT")),
        option(("-f", "--format"), str()),
        switch("-v", "--verbose"),
        arg(str(; metavar = "OUTPUT")),
    )

    val = parse_ok(parser, ["convert", "input.md", "-f", "json", "-v", "output.json"])
    @test val == ("convert", "input.md", "json", true, "output.json")
end

@testset "should not let control-only consuming matches satisfy tuple elements" begin
    parser = sequence(
        switch("-a"),
        arg(str()),
    )

    # `--` is consumed by the flag parser only to propagate option termination.
    # It must not count as satisfying the first tuple slot, so the tuple can
    # still parse the later positional argument. Completion should then fail
    # because the required flag was never matched semantically.
    err = parse_fail(parser, ["--", "hello"])
    @test err isa OptParse.ArgGateError
    @test err.code == OptParse.GATE_Missing
end

@testset "should propagate control-only consumption to later tuple elements" begin
    parser = sequence(
        optional(switch("-a")),
        arg(str()),
    )

    val = parse_ok(parser, ["--", "hello"])
    @test val == (nothing, "hello")
end
