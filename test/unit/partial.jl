@testset "skips unrecognized tokens and parses known flags" begin
    parser = partial(record((; verbose = default(flag("--verbose"), false))))
    result = tryoptparse(parser, ["--child-flag", "--verbose", "arg"])
    @test !is_error(result)
    val, remaining = unwrap(result)
    @test val.verbose == true
    @test remaining == ["--child-flag", "arg"]
end

@testset "returns defaults when nothing matches" begin
    parser = partial(record((;
        verbose = default(flag("--verbose"), false),
        port = default(option("--port", integer()), 8080),
    )))
    result = tryoptparse(parser, ["--child-flag", "arg"])
    @test !is_error(result)
    val, remaining = unwrap(result)
    @test val.verbose == false
    @test val.port == 8080
    @test remaining == ["--child-flag", "arg"]
end

@testset "propagates real errors (bad value)" begin
    parser = partial(record((;
        port = default(option("--port", integer()), 8080),
    )))
    result = tryoptparse(parser, ["--port", "abc"])
    @test is_error(result)
end

@testset "returns empty remaining when all tokens consumed" begin
    parser = partial(record((;
        verbose = default(flag("--verbose"), false),
        port = default(option("--port", integer()), 8080),
    )))
    result = tryoptparse(parser, ["--verbose", "--port", "9090"])
    @test !is_error(result)
    val, remaining = unwrap(result)
    @test val.verbose == true
    @test val.port == 9090
    @test remaining == String[]
end

@testset "handles empty argv" begin
    parser = partial(record((; verbose = default(flag("--verbose"), false))))
    result = tryoptparse(parser, String[])
    @test !is_error(result)
    val, remaining = unwrap(result)
    @test val.verbose == false
    @test remaining == String[]
end

@testset "preserves order of skipped tokens" begin
    parser = partial(record((; verbose = default(flag("--verbose"), false))))
    result = tryoptparse(parser, ["a", "b", "--verbose", "c"])
    @test !is_error(result)
    val, remaining = unwrap(result)
    @test val.verbose == true
    @test remaining == ["a", "b", "c"]
end

@testset "skips unrecognized options before a required option" begin
    parser = partial(record(; a = option("--verbose", integer())))
    result = tryoptparse(parser, String["--ignore", "--verbose", "123"])
    @test !is_error(result)
    val, remaining = unwrap(result)
    @test val.a == 123
    @test remaining == ["--ignore"]
end

@testset "skips multiple unrecognized tokens mixed with recognized ones" begin
    parser = partial(record(; a = option("--verbose", integer())))
    result = tryoptparse(parser, String["--foo", "--bar", "--verbose", "42", "extra"])
    @test !is_error(result)
    val, remaining = unwrap(result)
    @test val.a == 42
    @test remaining == ["--foo", "--bar", "extra"]
end

@testset "errors when parser recognizes option but value is invalid" begin
    parser = partial(record(; a = option("--verbose", integer())))
    result = tryoptparse(parser, String["--verbose", "abc"])
    @test is_error(result)
end
