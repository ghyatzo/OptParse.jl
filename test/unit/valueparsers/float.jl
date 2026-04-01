@testset "FloatVal" begin
    f = flt(Float32, min = 0.2, max = 120.3)
    @test (@? f("3.14")) == Float32(3.14)

    err = f("200")
    @test is_error(err) && occursin("maximum", string(unwrap_error(err)))
    err = f("0")
    @test is_error(err) && occursin("minimum", string(unwrap_error(err)))
    err = f("inf")
    @test is_error(err) && occursin("Infinite", string(unwrap_error(err)))
    err = f("nan")
    @test is_error(err) && occursin("NaNs", string(unwrap_error(err)))

    finfnan = flt(allowInfinity = true, allowNan = true)
    @test isinf(@? finfnan("-inf"))
    @test isnan(@? finfnan("nan"))

    @test_opt f("1.2")
end

@testset "FloatVal with positional metavar" begin
    f = flt("RATE", Float32, min = 0.2, max = 120.3)
    @test metavar(f) == "RATE"
    @test (@? f("3.14")) == Float32(3.14)

    defaultf = flt("VALUE", allowInfinity = true)
    @test metavar(defaultf) == "VALUE"
    @test isinf(@? defaultf("inf"))

    f32 = flt32("SMALL")
    @test metavar(f32) == "SMALL"

    f64 = flt64("LARGE")
    @test metavar(f64) == "LARGE"
end
