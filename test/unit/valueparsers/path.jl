@testset "PathVal with positional metavar" begin
    p = path("FILE")
    @test metavar(p) == "FILE"
end
