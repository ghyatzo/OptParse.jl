module GrayBox
    using OptParse: @parser, arg, str
    @parser struct GrayOpts
        @description "desc"
        @footer "foot"
        "Brief"
        a = arg(str())
    end
end

@testset "Correct hygiene" begin
    @test GrayBox.GrayOpts("x") isa GrayBox.GrayOpts
    @test optparse(GrayBox.GrayOpts, ["x"]) == GrayBox.GrayOpts("x")
end
