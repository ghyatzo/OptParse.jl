@testset "should create a parser with array-based API" begin
    parser = tup(
        flag("-v", "--verbose"),
        option(("-p", "--port"), integer()),
    )

    @test priority(parser) >= 10
    init = getproperty(parser, :initialState)
    @test init isa Tuple
    @test length(init) == 2
end

@testset "should parse parsers sequentially in array order" begin
    parser = tup(
        option(("-n", "--name"), str()),
        flag("-v", "--verbose"),
    )

    val = parse_ok(parser, ["-n", "Alice", "-v"])
    @test val == ("Alice", true)
end

@testset "should work with labeled tuples" begin
    parser = tup("User Data",
        option(("-n", "--name"), str()),
        flag("-v", "--verbose"),
    )

    val = parse_ok(parser, ["-n", "Bob", "-v"])
    @test val == ("Bob", true)
end

@testset "should handle empty tuple" begin
    parser = tup()  # empty tuple of parsers

    val = parse_ok(parser, String[])
    @test length(val) == 0
end

@testset "should work with optional parsers" begin
    parser = tup(
        option(("-n", "--name"), str()),
        optional(option(("-a", "--age"), integer())),
        flag("-v", "--verbose"),
    )

    val1 = parse_ok(parser, ["-n", "Alice", "-a", "30", "-v"])
    @test val1 == ("Alice", 30, true)

    val2 = parse_ok(parser, ["-n", "Bob", "-v"])
    @test val2 == ("Bob", nothing, true)
end

@testset "should work with arguments first, then options" begin
    parser = tup(
        argument(str()),
        flag("-v", "--verbose"),
        option(("-o", "--output"), str()),
    )

    val = parse_ok(parser, ["input.txt", "-v", "-o", "output.txt"])
    @test val == ("input.txt", true, "output.txt")
end

@testset "should work with multiple arguments and options mixed" begin
    parser = tup(
        argument(str()),
        argument(str()),
        flag("-v", "--verbose"),
    )

    val = parse_ok(parser, ["file1.txt", "file2.txt", "-v"])
    @test val == ("file1.txt", "file2.txt", true)
end

@testset "should handle argument-option-argument pattern" begin
    parser = tup(
        argument(str()),
        option(("-t", "--type"), str()),
        argument(str()),
    )

    val = parse_ok(parser, ["input.txt", "-t", "json", "output.txt"])
    @test val == ("input.txt", "json", "output.txt")
end

@testset "should fail when argument parser cannot find expected argument" begin
    parser = tup(
        argument(str()),
        flag("-v", "--verbose"),
    )

    # No arguments provided, should fail on first argument parser
    @test is_error(tryargparse(parser, ["-v"]))
end

@testset "should work with complex argument and option combinations" begin
    # CLI pattern: command input_file --format json --verbose output_file
    parser = tup(
        argument(str(; metavar = "COMMAND")),
        argument(str(; metavar = "INPUT")),
        option(("-f", "--format"), str()),
        flag("-v", "--verbose"),
        argument(str(; metavar = "OUTPUT")),
    )

    val = parse_ok(parser, ["convert", "input.md", "-f", "json", "-v", "output.json"])
    @test val == ("convert", "input.md", "json", true, "output.json")
end

@testset "should not let control-only consuming matches satisfy tuple elements" begin
    parser = tup(
        flag("-a"),
        argument(str()),
    )

    # `--` is consumed by the flag parser only to propagate option termination.
    # It must not count as satisfying the first tuple slot.
    err = parse_fail(parser, ["--", "hello"])
    @test err.domain == OptParse.ERR_ConstrTuple
    @test OptParse.TupleErrCode(err.code) == OptParse.TUPLE_NoRemainingParser
end

@testset "should propagate control-only consumption to later tuple elements" begin
    parser = tup(
        optional(flag("-a")),
        argument(str()),
    )

    val = parse_ok(parser, ["--", "hello"])
    @test val == (nothing, "hello")
end
