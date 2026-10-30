@testset "Trimming-compatible value formatting" begin
    for value in (
            "plain string", "quoted \"string\"\n", 42, true, nothing, 'x',
            (), (1,), (1, "two", false), ((1, 2), ()),
            "x" => (1, 2), "x" => (1,), "x" => (),
            "a\"b\n" => ("λ", '\n'),
            (1, 2) => ("x", false),
            ("x" => 1) => ("y" => 2),
            ("x" => (1, 2), ("y" => 3,)),
        )
        @test OptParse._trim_string(value) == string(value)
    end
    @test OptParse._trim_string(Pair{Any, Any}("x", (1, 2))) == "\"x\" => (1, 2)"
end
