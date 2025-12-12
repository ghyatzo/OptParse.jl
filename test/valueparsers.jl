@testset "StringVal" begin
    sval = str(metavar = "TEST", pattern = r"^A.*")
    @test (@? sval("AAA")) == "AAA"
    @test is_error(sval("BBB"))
    @test_opt sval("AAA")
end

@testset "Choice" begin
    ch = choice(["HELLO", "WoRlD"], metavar = "TEST", caseInsensitive = true)
    @test (@? ch("HELLO")) == "hello"
    @test (@? ch("world")) == "world"
    @test is_error(ch("!!!"))

    @test_opt ch("world")
end

@testset "IntegerVal" begin
    iv = integer(Int32, min = 10, max = 20)
    @test (@? iv("13")) == Int32(13)
    err = iv("3")
    @test is_error(err) && occursin("minimum", unwrap_error(err))
    err = iv("222")
    @test is_error(err) && occursin("maximum", unwrap_error(err))

    negiv = i64()
    @test (@? negiv("-12") == -12)

    @test_opt iv("15")
end

@testset "FloatVal" begin
    f = flt(Float32, min = 0.2, max = 120.3)
    @test (@? f("3.14")) == Float32(3.14)

    err = f("200")
    @test is_error(err) && occursin("maximum", unwrap_error(err))
    err = f("0")
    @test is_error(err) && occursin("minimum", unwrap_error(err))
    err = f("inf")
    @test is_error(err) && occursin("Infinite", unwrap_error(err))
    err = f("nan")
    @test is_error(err) && occursin("NaNs", unwrap_error(err))

    finfnan = flt(allowInfinity = true, allowNan = true)
    @test isinf(@? finfnan("-inf"))
    @test isnan(@? finfnan("nan"))

    @test_opt f("1.2")
end

@testset "UUIDVal" begin
    u = uuid(allowedVersions = [1, 4])
    u1 = string(uuid1())
    u4 = string(uuid4())
    u7 = string(uuid7())

    @test (@? u(u1)) == UUID(u1)
    @test uuid_version(@? u(u1)) == 1

    @test (@? u(u4)) == UUID(u4)
    @test uuid_version(@? u(u4)) == 4

    err = u(u7)
    @test is_error(err) && occursin("version", unwrap_error(err))

    @test_opt u(u1)
end
