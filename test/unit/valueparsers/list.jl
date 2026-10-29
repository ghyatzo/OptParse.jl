@testset "ListVal homogeneous" begin
    lv = list(integer(min = 0, max = 100), 3)
    @test metavar(lv) == "LIST"
    @test (@? lv("10,20,30")) === (10, 20, 30)

    err_few = lv("10,20")
    @test is_error(err_few) && occursin("Too few items", string(unwrap_error(err_few)))

    err_many = lv("10,20,30,40")
    @test is_error(err_many) && occursin("Too many items", string(unwrap_error(err_many)))

    err_elem = lv("10,200,30")
    @test is_error(err_elem) && occursin("maximum", string(unwrap_error(err_elem)))

    @test_opt lv("10,20,30")
end

@testset "ListVal heterogeneous" begin
    lv = list(str(), integer(), flt())
    @test (@? lv("foo,42,3.5")) == ("foo", 42, 3.5)

    err_elem = lv("foo,notanint,3.5")
    @test is_error(err_elem) && occursin("valid integer", string(unwrap_error(err_elem)))

    @test_opt lv("foo,42,3.5")
end

@testset "ListVal keywords and metavar" begin
    lv = list("COORDS", integer(), 2; separator = ':')
    @test metavar(lv) == "COORDS"
    @test (@? lv("10:20")) === (10, 20)

    lv2 = list("HOST_PORT", str(), integer(); separator = ':')
    @test metavar(lv2) == "HOST_PORT"
    @test (@? lv2("localhost:8080")) == ("localhost", 8080)

    @test_throws ArgumentError list(integer(), 2; separator = ' ')
    @test_throws ArgumentError list(integer(), flt(); separator = ' ')
end

@testset "ListVal with choice and nested list" begin
    ch_list = list(choice(["fast", "safe"]), 2)
    @test (@? ch_list("fast,safe")) == ("FAST", "SAFE")

    nested = list(list(integer(), 2; separator = ':'), 2)
    @test (@? nested("1:2,3:4")) === ((1, 2), (3, 4))
    @test_opt nested("1:2,3:4")
end
