@testset "Choice" begin
    ch = choice(["HELLO", "WoRlD"], metavar = "TEST", caseInsensitive = true)
    @test (@? ch("HELLO")) == "hello"
    @test (@? ch("world")) == "world"
    @test is_error(ch("!!!"))

    @test_opt ch("world")
end
