@enum Mode begin
    Debug
    Release
end

@enum Level begin
    Low = 10
    High = 20
end

@testset "Choice" begin
    ch = choice(["HELLO", "WoRlD"], metavar = "TEST", case_insensitive = true)
    @test (@? ch("HELLO")) == "HELLO"
    @test (@? ch("world")) == "WORLD"
    @test is_error(ch("!!!"))

    @test_opt ch("world")
end

@testset "Choice with positional metavar" begin
    ch = choice("TEST", ["HELLO", "WoRlD"], case_insensitive = true)
    @test metavar(ch) == "TEST"
    @test (@? ch("world")) == "WORLD"
end

@testset "Choice enum" begin
    ch = choice(Mode; case_insensitive = true)

    @test (@? ch("Debug")) == Debug
    @test (@? ch("release")) == Release
    @test is_error(ch("nope"))

    @test_opt ch("debug")
end

@testset "Choice enum with explicit values" begin
    ch = choice(Level; case_insensitive = true)

    @test (@? ch("low")) == Low
    @test (@? ch("HIGH")) == High
    @test is_error(ch("medium"))
end

@testset "Choice enum with positional metavar" begin
    ch = choice("MODE", Mode; case_insensitive = true)
    @test metavar(ch) == "MODE"
    @test (@? ch("release")) == Release
end

@testset "usage_annotations" begin
    ch = choice(["fast", "safe"])
    @test OptParse.usage_annotations(ch) == ["choices: fast, safe"]

    ch2 = choice(Mode)
    @test OptParse.usage_annotations(ch2) == ["choices: debug, release"]
end
