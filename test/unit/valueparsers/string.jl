@testset "StringVal" begin
    sval = str(metavar = "TEST", pattern = r"^A.*")
    @test (@? sval("AAA")) == "AAA"
    @test is_error(sval("BBB"))

    smeta = str("NAME", pattern = r"^A.*")
    @test metavar(smeta) == "NAME"
    @test (@? smeta("ABC")) == "ABC"

    @test_opt sval("AAA")
end
