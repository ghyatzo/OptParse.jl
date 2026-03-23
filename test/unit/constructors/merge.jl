@testset "should merge object parsers into a single parser" begin
    parser = objmerge(
        object((
            verbose = flag("-v", "--verbose"),
        )),
        object((
            port = option(("-p", "--port"), integer()),
        )),
    )

    @test hasproperty(parser, :initialState)
    names = propertynames(parser.initialState)
    @test :verbose in names
    @test :port in names

    result = argparse(parser, ["-v", "--port", "8080"])
    @test !is_error(result)

    val = unwrap(result)
    @test val.verbose == true
    @test val.port == 8080
end

@testset "should work with labeled merged objects" begin
    parser = objmerge(
        "network",
        object((
            host = option("--host", str()),
        )),
        object((
            port = option("--port", integer()),
        )),
    )

    result = argparse(parser, ["--host", "localhost", "--port", "8080"])
    @test !is_error(result)

    val = unwrap(result)
    @test val.host == "localhost"
    @test val.port == 8080
end

@testset "should fail when merged objects have duplicate field names" begin
    @test_throws Exception objmerge(
        object((name = option("--name", str()),)),
        object((name = option("--other-name", str()),)),
    )
end
