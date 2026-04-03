@testset "should return false when optional flag is absent" begin
    @test parse_ok(flag("-v"), String[]) == false
end

@testset "should return true when optional flag is present" begin
    @test parse_ok(flag("-v"), ["-v"]) == true
end

@testset "should support multiple optional flag names" begin
    parser = flag("-v", "--verbose")
    @test parse_ok(parser, ["-v"]) == true
    @test parse_ok(parser, ["--verbose"]) == true
    @test parse_ok(parser, String[]) == false
end

@testset "should propagate option termination through optional flags" begin
    @test parse_ok(flag("-v"), ["--"]) == false
    @test is_error(tryargparse(flag("-v"), ["--", "-v"]))
end

@testset "should be type stable" begin
    @test_opt flag("-v")
    @test_opt argparse(flag("-v"), ["-v"])
    @test_opt argparse(flag("-v"), String[])
end
