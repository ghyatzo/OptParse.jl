@testset "should concatenate tuple parsers into a flat tuple" begin
    parser = concat(
        sequence(
            option("-x", integer()),
            option("-y", integer()),
        ),
        sequence(
            arg(str()),
        ),
    )

    val = parse_ok(parser, ["-y", "20", "-x", "10", "input.txt"])
    @test val == (10, 20, "input.txt")
end

@testset "should work with labeled concatenated tuples" begin
    parser = concat(
        sequence(option("--host", str())),
        sequence(option("--port", integer())),
        label = "connection",
    )

    val = parse_ok(parser, ["--host", "localhost", "--port", "8080"])
    @test val == ("localhost", 8080)
end

@testset "should support concatenating more than two tuple parsers" begin
    parser = concat(
        sequence(option("-u", str())),
        sequence(option("-p", str())),
        sequence(gate("-v")),
    )

    val = parse_ok(parser, ["-u", "user", "-p", "pass", "-v"])
    @test val == ("user", "pass", true)
end
