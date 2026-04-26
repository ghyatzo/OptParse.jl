@testset "should create a parser that always returns the same value" begin
    parser = @constant(42)

    @test priority(parser) == 0
    @test parser.initialState == Val(42)
end

@testset "should parse without consuming any input" begin
    parser = @constant(:hello)
    context = mkctx(["--option", "value"], Val(:hello))

    result = splitparse(parser, context)
    @test !is_error(result)
    succ = unwrap(result)
    @test res_consumed(succ) == consumed_empty(context)
    @test res_nextctx(succ) == context
end

# @test "should fail when passed strings" begin
#     @test_throws "Symbol" @constant("hello")
# end

@testset "should complete successfully with a constant value" begin
    parser = @constant(69)
    result = splitcomplete(parser, Val(69))

    @test !is_error(result)
    @test val(unwrap(result)) == 69
end
@testset "should work with different value types" begin
    stringconst = @constant(:hello)
    intconst = @constant(123)
    boolconst = @constant(true)
    namedtupleconst = @constant((key = :value,))

    @test val(@? complete(unwrapunion(stringconst), Val(:hello))) == :hello
    @test val(@? complete(unwrapunion(intconst), Val(123))) == 123
    @test val(@? complete(unwrapunion(boolconst), Val(true))) == true
    @test val(@? complete(unwrapunion(namedtupleconst), Val((key = :value,)))) == (key = :value,)
end

@testset "should be type stable" begin
    @test_opt @constant(:hello)
    @test_opt @constant(123)
    @test_opt @constant(true)
    @test_opt @constant((key = :value,))

    @test_opt optparse(@constant(10), String[])
end
