@testset "IntegerVal" begin
    iv = integer(Int32, min = 10, max = 20)
    @test (@? iv("13")) == Int32(13)
    err = iv("3")
    @test is_error(err) && occursin("minimum", string(unwrap_error(err)))
    err = iv("222")
    @test is_error(err) && occursin("maximum", string(unwrap_error(err)))

    negiv = i64()
    @test (@? negiv("-12")) == -12

    @test_opt iv("15")
end
