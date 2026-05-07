@testset "should combine record parsers into a single parser" begin
    parser = combine(
        record((
            verbose = switch("-v", "--verbose"),
        )),
        record((
            port = option(("-p", "--port"), integer()),
        )),
    )

    names = propertynames(parser.initialState)
    @test :verbose in names
    @test :port in names

    val = parse_ok(parser, ["-v", "--port", "8080"])
    @test val.verbose == true
    @test val.port == 8080
end

@testset "should work with labeled combined records" begin
    parser = combine(
        "network",
        record((
            host = option("--host", str()),
        )),
        record((
            port = option("--port", integer()),
        )),
    )

    val = parse_ok(parser, ["--host", "localhost", "--port", "8080"])
    @test val.host == "localhost"
    @test val.port == 8080
end

@testset "should fail when combined records have duplicate field names" begin
    @test_throws Exception combine(
        record((name = option("--name", str()),)),
        record((name = option("--other-name", str()),)),
    )
end
