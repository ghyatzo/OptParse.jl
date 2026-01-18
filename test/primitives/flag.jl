@testset "should parse single short flag" begin
    parser = flag("-v")
    context = Context(buffer=["-v"], state= parser.initialState)

    result = @unionsplit parse(parser, context)

    @test is_ok_and(result) do succ
        is_ok_and(==(true), succ.next.state)
    end
    succ = unwrap(result)
    @test succ.next.buffer == String[]
    @test succ.consumed == ("-v",)
end

@testset "should parse long flag" begin
    parser = flag("--verbose")
    context = Context(buffer=["--verbose"], state= parser.initialState)

    result = @unionsplit parse(parser, context)

    @test is_ok_and(result) do succ
        is_ok_and(==(true), succ.next.state)
    end
    succ = unwrap(result)
    @test succ.next.buffer == String[]
    @test succ.consumed == ("--verbose",)
end

@testset "should parse multiple flag names" begin
    parser = flag("-v", "--verbose")

    # First: "-v"
    context1 = Context(buffer=["-v"], state= parser.initialState)
    result1 = @unionsplit parse(parser, context1)
    @test is_ok_and(result1) do succ
        is_ok_and(==(true), succ.next.state)
    end

    # Second: "--verbose"
    context2 = Context(buffer=["--verbose"], state= parser.initialState)
    result2 = @unionsplit parse(parser, context2)
    @test is_ok_and(result2) do succ
        is_ok_and(==(true), succ.next.state)
    end
end

@testset "should fail when flag is already set" begin
    parser = flag("-v")
    # Represent "already set" using Result-based state:
    context = Context(buffer=["-v"], state= Result{Bool, String}(Ok(true)))

    result = @unionsplit parse(parser, context)

    @test is_error(result)
    unwrap_or_else(result) do fail
        @test fail.consumed == 1
        @test occursin("cannot be used multiple times", fail.error)
    end
end

@testset "should handle bundled short flags" begin
    parser = flag("-v")
    context = Context(buffer=["-vd"], state= parser.initialState)

    result = @unionsplit parse(parser, context)

    @test is_ok_and(result) do succ
        is_ok_and(==(true), succ.next.state)
    end
    succ = unwrap(result)
    @test succ.next.buffer == ["-d"]
    @test succ.consumed == ("-v",)
end

@testset "should fail when flags are terminated" begin
    parser = flag("-v")
    context = Context(buffer=["-v"], state= parser.initialState, optionsTerminated=true)

    result = @unionsplit parse(parser, context)

    @test is_error(result)
    unwrap_or_else(result) do fail
        @test fail.consumed == 0
        @test occursin("No more", fail.error)
    end
end

@testset "should handle flags terminator --" begin
    parser = flag("-v")
    context = Context(buffer=["--"], state=parser.initialState)

    result = @unionsplit parse(parser, context)

    @test !is_error(result)
    is_ok_and(result) do succ
        @test succ.next.optionsTerminated == true
        @test succ.next.buffer == String[]
        @test succ.consumed == ("--",)
        true
    end
end

@testset "should handle option terminator edge cases correctly" begin
    parser = flag("-v")

    result = argparse(parser, ["--", "-v"])
    @test is_error(result)
    @test occursin("No more options", unwrap_error(result))

    result = argparse(parser, ["--"])
    @test is_error(result)
    @test occursin("Missing", unwrap_error(result))

    result = argparse(parser, ["-v", "--"])
    @test !is_error(result)
    @test (@? result) == true
end

@testset "should handle empty buffer" begin
    parser = flag("-v")
    context = Context(buffer=String[], state=parser.initialState)

    result = @unionsplit parse(parser, context)

    @test is_error(result)
    unwrap_or_else(result) do fail
        @test fail.consumed == 0
        @test occursin("Expected a", fail.error)
    end
end

@testset "should be type stable" begin
    @test_opt flag("-v")
    parser = flag("-v")

    @test_opt argparse(parser, ["-v"])
end
