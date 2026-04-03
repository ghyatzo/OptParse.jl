@testset "should combine object parsers into a single parser" begin
    parser = combine(
        object((
            verbose = gate("-v", "--verbose"),
        )),
        object((
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

@testset "should work with labeled combined objects" begin
    parser = combine(
        "network",
        object((
            host = option("--host", str()),
        )),
        object((
            port = option("--port", integer()),
        )),
    )

    val = parse_ok(parser, ["--host", "localhost", "--port", "8080"])
    @test val.host == "localhost"
    @test val.port == 8080
end

@testset "should fail when combined objects have duplicate field names" begin
    @test_throws Exception combine(
        object((name = option("--name", str()),)),
        object((name = option("--other-name", str()),)),
    )
end
