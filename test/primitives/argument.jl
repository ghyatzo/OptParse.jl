
@testset "should create a parser that expects a single argument" begin
    parser = argument(str(; metavar="FILE"))

    @test priority(parser) == 5
    @test getproperty(parser, :initialState) === none(Result{String,String})
end

@testset "should parse a string argument" begin
    parser = argument(str(; metavar="FILE"))
    state = getproperty(parser, :initialState)
    ctx = Context(["myfile.txt"], state)

    res = parse(parser, ctx)
    @test !is_error(res)

    succ = unwrap(res)
    next = getproperty(succ, :next)

    st = getproperty(next, :state)
    @test !is_error(unwrap(st))
    @test unwrap(unwrap(st)) == "myfile.txt"

    @test getproperty(next, :buffer) == String[]
    @test getproperty(succ, :consumed) == ("myfile.txt",)
end

@testset "should parse an integer argument" begin
    parser = argument(integer(; min=0))
    state = getproperty(parser, :initialState)
    ctx = Context(["42"], state)

    res = parse(parser, ctx)
    @test !is_error(res)

    succ = unwrap(res)
    next = getproperty(succ, :next)

    st = getproperty(next, :state)
    @test !is_error(unwrap(st))
    @test unwrap(unwrap(st)) == 42

    @test getproperty(next, :buffer) == String[]
    @test getproperty(succ, :consumed) == ("42",)
end

@testset "should fail when buffer is empty" begin
    parser = argument(str(; metavar="FILE"))
    state = getproperty(parser, :initialState)
    ctx = Context(String[], state)

    res = parse(parser, ctx)
    @test is_error(res)

    err = unwrap_error(res)
    @test getproperty(err, :consumed) == 0
    @test occursin("Expected argument", string(err.error))
end

@testset "should propagate value parser failures" begin
    parser = argument(integer(; min=1, max=100))
    state = getproperty(parser, :initialState)
    ctx = Context(["invalid"], state)

    res = parse(parser, ctx)
    @test !is_error(res)

    succ = unwrap(res)
    st = getproperty(getproperty(succ, :next), :state)
    @test st !== nothing
    @test is_error(unwrap(st))
end

@testset "should complete successfully with valid state" begin
    parser = argument(str(; metavar="FILE"))
    validState = some(Result{String,String}(Ok("test.txt")))

    res = complete(parser, validState)
    @test !is_error(res)
    @test unwrap(res) == "test.txt"
end

@testset "should fail completion with invalid state" begin
    parser = argument(str(; metavar="FILE"))
    invalidState = some(Result{String,String}(Err("Missing argument")))

    res = complete(parser, invalidState)
    @test is_error(res)
    @test occursin("Missing argument", string(unwrap_error(res)))
end

@testset "should work with different value parser constraints" begin
    fileParser = argument(str(; pattern=r"\.(txt|md)$"))
    portParser = argument(integer(; min=1024, max=0xffff))

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

@testset "should be type stable" begin
    @test_opt argument(str(; pattern=r"\.(txt|md)$"))
    fileParser = argument(str(; pattern=r"\.(txt|md)$"))
    @test_opt argument(integer(; min=1024, max=0xffff))
    portParser = argument(integer(; min=1024, max=0xffff))

    @test_opt argparse(fileParser, ["readme.txt"])
    @test_opt argparse(portParser, ["8080"])
end