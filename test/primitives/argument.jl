@testset "should create a parser that expects a single argument" begin
    parser = argument(str(; metavar = "FILE"))

    @test priority(parser) == 5
    @test getproperty(unwrapunion(parser), :initialState) === none(Result{String, String})
end

@testset "should parse a string argument" begin
    parser = argument(str(; metavar = "FILE"))
    state = parser.initialState
    buffer = ["myfile.txt"]
    ctx = Context(;buffer, state)

    res = parse(unwrapunion(parser), ctx)
    @test !is_error(res)

    succ = unwrap(res)
    next = ℒ_nextctx(succ)

    st = ℒ_state(next)
    @test !is_error(unwrap(st))
    @test unwrap(unwrap(st)) == "myfile.txt"

    @test ctx_remaining(next) == String[]
    @test as_tuple(ℒ_consumed(succ)) == ("myfile.txt",)
end

@testset "should parse an integer argument" begin
    parser = argument(integer(; min = 0))
    state = parser.initialState
    buffer = ["42"]
    ctx = Context(;buffer, state)

    res = parse(unwrapunion(parser), ctx)
    @test !is_error(res)

    succ = unwrap(res)
    next = ℒ_nextctx(succ)

    st = ℒ_state(next)
    @test !is_error(unwrap(st))
    @test unwrap(unwrap(st)) == 42

    @test ctx_remaining(next) == String[]
    @test as_tuple(ℒ_consumed(succ)) == ("42",)
end

@testset "should fail when buffer is empty" begin
    parser = argument(str(; metavar = "FILE"))
    state = parser.initialState
    buffer = String[]
    ctx = Context(; buffer, state)

    res = parse(unwrapunion(parser), ctx)
    @test is_error(res)

    err = unwrap_error(res)
    @test ℒ_nconsumed(err) == 0
    @test occursin("Expected an argument", string(err.error))
end

@testset "should propagate value parser failures" begin
    parser = argument(integer(; min = 1, max = 100))
    state = getproperty(unwrapunion(parser), :initialState)
    buffer = ["invalid"]
    ctx = Context(;buffer, state)

    res = parse(unwrapunion(parser), ctx)
    @test !is_error(res)

    succ = unwrap(res)
    st = ℒ_nextstate(succ)
    @test st !== nothing
    @test is_error(unwrap(st))
end

@testset "should complete successfully with valid state" begin
    parser = argument(str(; metavar = "FILE"))
    validState = some(Result{String, String}(Ok("test.txt")))

    res = complete(unwrapunion(parser), validState)
    @test !is_error(res)
    @test unwrap(res) == "test.txt"
end

@testset "should fail completion with invalid state" begin
    parser = argument(str(; metavar = "FILE"))
    invalidState = some(Result{String, String}(Err("Missing argument")))

    res = complete(unwrapunion(parser), invalidState)
    @test is_error(res)
    @test occursin("Missing argument", string(unwrap_error(res)))
end

@testset "should work with different value parser constraints" begin
    fileParser = argument(str(; pattern = r"\.(txt|md)$"))
    portParser = argument(integer(; min = 1024, max = 0xffff))

    # valid file
    validFileRes = argparse(fileParser, ["readme.txt"])
    @test !is_error(validFileRes)
    begin

        @test unwrap(validFileRes) == "readme.txt"
    end

    # invalid file
    invalidFileRes = argparse(fileParser, ["script.js"])
    @test is_error(invalidFileRes) || is_error(getproperty(unwrap(invalidFileRes).next, :state))

    # valid port
    validPortRes = argparse(portParser, ["8080"])
    @test !is_error(validPortRes)
    begin
        @test unwrap(validPortRes) == 8080
    end

    # invalid port
    invalidPortRes = argparse(portParser, ["80"])
    @test is_error(invalidPortRes) || is_error(getproperty(unwrap(invalidPortRes).next, :state))
end

@testset "should handle -- edge cases correctly" begin
    parser = argument(str())

    result = argparse(parser, ["--", "abc"])
    @test !is_error(result)
    @test (@? result) == "abc"

    ctx = Context(buffer=["abc", "--"], state=parser.initialState)
    presult = splitparse(parser, ctx)
    @test !is_error(presult)
    
    pok = unwrap(presult)
    @test as_tuple(ℒ_consumed(pok)) == ("abc",)
    @test ctx_remaining(ℒ_nextctx(pok)) == ["--"]

    val = splitcomplete(parser, ℒ_nextstate(pok))
    @test (@? val) == "abc"

    result = argparse(parser, ["--"])
    @test is_error(result)
    @test occursin("Expected", unwrap_error(result))
end

@testset "should be type stable" begin
    @test_opt argument(str(; pattern = r"\.(txt|md)$"))
    fileParser = argument(str(; pattern = r"\.(txt|md)$"))
    @test_opt argument(integer(; min = 1024, max = 0xffff))
    portParser = argument(integer(; min = 1024, max = 0xffff))

    @test_opt argparse(fileParser, ["readme.txt"])
    @test_opt argparse(portParser, ["8080"])
end
