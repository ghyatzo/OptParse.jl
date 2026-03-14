@testset "should expand bundled short flags before terminator" begin
    expanded, origin = OptParse.normalize_argv(["-abc", "--name", "alice"])

    @test expanded == ["-a", "-b", "-c", "--name", "alice"]
    @test origin == [1, 1, 1, 2, 3]
end

@testset "should leave long options untouched" begin
    expanded, origin = OptParse.normalize_argv(["--port=8080", "--verbose"])

    @test expanded == ["--port=8080", "--verbose"]
    @test origin == [1, 2]
end

@testset "should stop expanding bundled short flags after terminator" begin
    expanded, origin = OptParse.normalize_argv(["-ab", "--", "-cd"])

    @test expanded == ["-a", "-b", "--", "-cd"]
    @test origin == [1, 1, 2, 3]
end

@testset "should preserve single short options and positional arguments" begin
    expanded, origin = OptParse.normalize_argv(["-v", "input.txt", "-x"])

    @test expanded == ["-v", "input.txt", "-x"]
    @test origin == [1, 2, 3]
end
