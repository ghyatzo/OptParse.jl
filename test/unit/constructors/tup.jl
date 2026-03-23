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

    res = argparse(parser, ["-n", "Alice", "-v"])
    @test !is_error(res)

    val = unwrap(res)
    @test val == ("Alice", true)
end

@testset "should work with labeled tuples" begin
    parser = tup("User Data",
        option(("-n", "--name"), str()),
        flag("-v", "--verbose"),
    )

    res = argparse(parser, ["-n", "Bob", "-v"])
    @test !is_error(res)

    val = unwrap(res)
    @test val == ("Bob", true)
end

@testset "should handle empty tuple" begin
    parser = tup()  # empty tuple of parsers

    res = argparse(parser, String[])
    @test !is_error(res)

    val = unwrap(res)
    @test length(val) == 0
end

@testset "should work with optional parsers" begin
    parser = tup(
        option(("-n", "--name"), str()),
        optional(option(("-a", "--age"), integer())),
        flag("-v", "--verbose"),
    )

    res1 = argparse(parser, ["-n", "Alice", "-a", "30", "-v"])
    @test !is_error(res1)
    val1 = unwrap(res1)
    @test val1 == ("Alice", 30, true)

    res2 = argparse(parser, ["-n", "Bob", "-v"])
    @test !is_error(res2)
    val2 = unwrap(res2)
    @test val2 == ("Bob", nothing, true)
end

@testset "should work with arguments first, then options" begin
    parser = tup(
        argument(str()),
        flag("-v", "--verbose"),
        option(("-o", "--output"), str()),
    )

    res = argparse(parser, ["input.txt", "-v", "-o", "output.txt"])
    @test !is_error(res)

    val = unwrap(res)
    @test val == ("input.txt", true, "output.txt")
end

@testset "should work with multiple arguments and options mixed" begin
    parser = tup(
        argument(str()),
        argument(str()),
        flag("-v", "--verbose"),
    )

    res = argparse(parser, ["file1.txt", "file2.txt", "-v"])
    @test !is_error(res)

    val = unwrap(res)
    @test val == ("file1.txt", "file2.txt", true)
end

@testset "should handle argument-option-argument pattern" begin
    parser = tup(
        argument(str()),
        option(("-t", "--type"), str()),
        argument(str()),
    )

    res = argparse(parser, ["input.txt", "-t", "json", "output.txt"])
    @test !is_error(res)

    val = unwrap(res)
    @test val == ("input.txt", "json", "output.txt")
end

@testset "should fail when argument parser cannot find expected argument" begin
    parser = tup(
        argument(str()),
        flag("-v", "--verbose"),
    )

    # No arguments provided, should fail on first argument parser
    res = argparse(parser, ["-v"])
    @test is_error(res)
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

    res = argparse(parser, ["convert", "input.md", "-f", "json", "-v", "output.json"])
    @test !is_error(res)

    val = unwrap(res)
    @test val == ("convert", "input.md", "json", true, "output.json")
end