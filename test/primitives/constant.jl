@testset "should create a parser that always returns the same value" begin
    parser = @constant(42)

    @test priority(parser) == 0
    @test parser.initialState == Val(42)
end

@testset "should parse without consuming any input" begin
    parser = @constant(:hello)
    context = Context(["--option", "value"], Val(:hello))

    result = @unionsplit parse(parser, context)
    @test is_ok_and(result) do succ
        @test succ.consumed == ()
        @test succ.next == context
        !is_error(result)
    end
end

# @test "should fail when passed strings" begin
#     @test_throws "Symbol" @constant("hello")
# end

@testset "should complete successfully with a constant value" begin
    parser = @constant(69)
    result = @unionsplit complete(parser,Val(69))

    @test is_ok_and(result) do succ
        @test succ == 69
        !is_error(result)
    end
end
@testset "should work with different value types" begin
    stringconst = @constant(:hello)
    intconst = @constant(123)
    boolconst = @constant(true)
    namedtupleconst = @constant((key = :value,))

    @test (@? complete(unwrapunion(stringconst), Val(:hello))) == :hello
    @test (@? complete(unwrapunion(intconst), Val(123))) == 123
    @test (@? complete(unwrapunion(boolconst), Val(true))) == true
    @test (@? complete(unwrapunion(namedtupleconst), Val((key = :value,)))) == (key = :value,)
end

@testset "should be type stable" begin
    @test_opt @constant(:hello)
    @test_opt @constant(123)
    @test_opt @constant(true)
    @test_opt @constant((key = :value,))

    @test_opt argparse(@constant(10), String[])
end
