@testset "PairVal" begin
    pv = pair(str("KEY"), integer("VALUE"))
    @test metavar(pv) == "KEY=VALUE"
    @test val_t(pv) == Pair{String, Int}
    @test (@? pv("answer=42")) == ("answer" => 42)

    err_few = pv("answer")
    @test is_error(err_few) && occursin("Too few items", string(unwrap_error(err_few)))

    err_many = pv("answer=42=extra")
    @test is_error(err_many) && occursin("Too many items", string(unwrap_error(err_many)))

    err_elem = pv("answer=notanint")
    @test is_error(err_elem) && occursin("valid integer", string(unwrap_error(err_elem)))

    @test_opt pv("answer=42")
end

@testset "PairVal keywords and metavar" begin
    pv = pair("HOST:PORT", str(), integer(); separator = ':')
    @test metavar(pv) == "HOST:PORT"
    @test (@? pv("localhost:8080")) == ("localhost" => 8080)

    @test_throws ArgumentError pair(str(), integer(); separator = ' ')
end

@testset "PairVal with nested list" begin
    nested = pair(str(), list(integer(), integer()))
    @test (@? nested("coords=1,2")) == ("coords" => (1, 2))

    @test_opt nested("coords=1,2")
end
