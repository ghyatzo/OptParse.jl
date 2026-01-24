@testset "should parse option with separated value" begin
    parser = option(("-p", "--port"), integer())
    context = Context(buffer=["--port", "8080"], state=parser.initialState)

    res = @unionsplit parse(parser, context)  # :: ParseResult

    @test !is_error(res)  # success
    ps = unwrap(res)      # :: ParseSuccess

    # next.state should itself be a successful value (Result/Option)
    @test !is_error(ℒ_state(ps.next))
    @test unwrap(ℒ_state(ps.next)) == 8080

    @test ctx_remaining(ps.next) == String[]  # buffer consumed
    @test ps.consumed == ("--port", "8080")  # tuple, not Vector
end

@testset "should parse option with equals-separated value" begin
    parser = option("--port", integer())
    context = Context(buffer=["--port=8080"], state=parser.initialState)

    res = @unionsplit parse(parser, context)

    @test !is_error(res)
    ps = unwrap(res)

    @test !is_error(ℒ_state(ps.next))
    @test unwrap(ℒ_state(ps.next)) == 8080

    @test ctx_remaining(ps.next) == String[]
    @test ps.consumed == ("--port=8080",)
end

@testset "should handle option terminator edge cases correctly" begin
    parser = option("--name", str())

    result = argparse(parser, ["--", "--name", "lol"])
    @test is_error(result)
    @test occursin("No more options", unwrap_error(result))

    result = argparse(parser, ["--"])
    @test is_error(result)
    @test occursin("Missing", unwrap_error(result))

    result = argparse(parser, ["--name", "--"])
    @test is_error(result)
    @test occursin("value", unwrap_error(result))

    result = argparse(parser, ["--name", "bob", "--"])
    @test !is_error(result)
    @test (@? result) == "bob"
end

# @testset "should parse DOS-style option with colon" begin
#     parser  = option("/P", integer())
#     context = Context(buffer=["/P:8080"], state=parser.initialState)

#     res = @unionsplit parse(parser, context)

#     @test !is_error(res)
#     ps = unwrap(res)

#     @test !is_error(ℒ_state(ps.next))
#     @test unwrap(ℒ_state(ps.next)) == 8080
#     # TS test does not check buffer/consumed here
# end

@testset "should fail when value is missing" begin
    parser = option("--port", integer())
    context = Context(buffer=["--port"], state=parser.initialState)

    res = @unionsplit parse(parser, context)

    @test is_error(res)  # failure
    pf = unwrap_error(res)  # :: ParseFailure

    @test pf.consumed == 1
    @test occursin("requires a value", string(pf.error))
end

@testset "should parse string values" begin
    parser = option("--name", str(; metavar = "NAME"))
    context = Context(buffer=["--name", "Alice"], state=parser.initialState)

    res = @unionsplit parse(parser, context)

    @test !is_error(res)
    ps = unwrap(res)

    @test !is_error(ℒ_state(ps.next))
    @test unwrap(ℒ_state(ps.next)) == "Alice"
end

@testset "should propagate value parser failures" begin
    parser = option("--port", integer(; min = 1, max = 0xffff))
    context = Context(buffer=["--port", "invalid"], state=parser.initialState)

    res = @unionsplit parse(parser, context)

    # Option itself matched, so overall parse succeeds...
    @test !is_error(res)
    ps = unwrap(res)

    # ...but the inner value parser failed (carry failure in state)
    @test is_error(ℒ_state(ps.next))
    @test occursin("Expected valid integer", string(unwrap_error(ℒ_state(ps.next))))
end

@testset "should fail on unmatched option" begin
    parser = option(("-v", "--verbose"), choice(["yes", "no"]))
    context = Context(buffer=["--help"], state=parser.initialState)

    res = @unionsplit parse(parser, context)

    @test is_error(res)
    pf = unwrap_error(res)

    @test pf.consumed == 0
    @test occursin("No Matched", string(pf.error))
end

@testset "should be type stable" begin
    @test_opt option("--port", integer())
    parser = option("--port", integer())

    @test_opt argparse(parser, ["--port", "8080"])
end
