@testset "should concatenate tuple parsers into a flat tuple" begin
    parser = concat(
        tup(
            option("-x", integer()),
            option("-y", integer()),
        ),
        tup(
            argument(str()),
        ),
    )

    result = argparse(parser, ["-y", "20", "-x", "10", "input.txt"])
    @test !is_error(result)

    val = unwrap(result)
    @test val == (10, 20, "input.txt")
end

@testset "should work with labeled concatenated tuples" begin
    parser = concat(
        tup(option("--host", str())),
        tup(option("--port", integer())),
        label = "connection",
    )

    result = argparse(parser, ["--host", "localhost", "--port", "8080"])
    @test !is_error(result)

    val = unwrap(result)
    @test val == ("localhost", 8080)
end

@testset "should support concatenating more than two tuple parsers" begin
    parser = concat(
        tup(option("-u", str())),
        tup(option("-p", str())),
        tup(flag("-v")),
    )

    result = argparse(parser, ["-u", "user", "-p", "pass", "-v"])
    @test !is_error(result)

    val = unwrap(result)
    @test val == ("user", "pass", true)
end
