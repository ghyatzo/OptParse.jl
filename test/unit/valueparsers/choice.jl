@enum Mode begin
    Debug
    Release
end

@enum Level begin
    Low = 10
    High = 20
end

@testset "Choice" begin
    ch = choice(["HELLO", "WoRlD"], metavar = "TEST", caseInsensitive = true)
    @test (@? ch("HELLO")) == "HELLO"
    @test (@? ch("world")) == "WORLD"
    @test is_error(ch("!!!"))

    @test_opt ch("world")
end

@testset "Choice with positional metavar" begin
    ch = choice("TEST", ["HELLO", "WoRlD"], caseInsensitive = true)
    @test metavar(ch) == "TEST"
    @test (@? ch("world")) == "WORLD"
end

@testset "Choice enum" begin
    ch = choice(Mode; caseInsensitive = true)

    @test (@? ch("Debug")) == Debug
    @test (@? ch("release")) == Release
    @test is_error(ch("nope"))

    @test_opt ch("debug")
end

@testset "Choice enum with explicit values" begin
    ch = choice(Level; caseInsensitive = true)

    @test (@? ch("low")) == Low
    @test (@? ch("HIGH")) == High
    @test is_error(ch("medium"))
end

@testset "Choice enum with positional metavar" begin
    ch = choice("MODE", Mode; caseInsensitive = true)
    @test metavar(ch) == "MODE"
    @test (@? ch("release")) == Release
end
