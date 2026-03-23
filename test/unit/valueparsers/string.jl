@testset "StringVal" begin
    sval = str(metavar = "TEST", pattern = r"^A.*")
    @test (@? sval("AAA")) == "AAA"
    @test is_error(sval("BBB"))
    @test_opt sval("AAA")
end
