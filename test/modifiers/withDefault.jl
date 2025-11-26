@testset "should create a parser with same priority as wrapped parser" begin
    baseParser = flag("-v", "--verbose")
    defaultParser = withDefault(baseParser, false)

    @test priority(defaultParser) == priority(baseParser)
    @test getproperty(defaultParser, :initialState) === none(tstate(baseParser))
end

@testset "should return wrapped parser value when it succeeds" begin
    baseParser = flag("-v", "--verbose")
    defaultParser = withDefault(baseParser, false)

    buffer = ["-v"]
    state = defaultParser.initialState
    ctx = Context(buffer, state)

    parseResult = splitparse(defaultParser, ctx)
    @test !is_error(parseResult)
    if !is_error(parseResult)
        next_state = unwrap(parseResult).next.state
        completeResult = splitcomplete(defaultParser, next_state)
        @test !is_error(completeResult)
        if !is_error(completeResult)
            @test unwrap(completeResult) === true
        end
    end
end

@testset "should return default value when parser doesn't match" begin
    baseParser = flag("-v", "--verbose")
    defaultValue = false
    defaultParser = withDefault(baseParser, defaultValue)

    completeResult = splitcomplete(defaultParser, none(tstate(baseParser)))
    @test !is_error(completeResult)
    if !is_error(completeResult)
        @test unwrap(completeResult) === defaultValue
    end
end

# @testset "should work with function-based default values" begin
#     call_count = Ref(0)
#     defaultFunction = () -> begin
#         call_count[] += 1
#         call_count[] > 1
#     end

#     baseParser = flag("-v", "--verbose")
#     defaultParser = withDefault(baseParser, defaultFunction)

#     # First call
#     completeResult1 = splitcomplete(defaultParser, nothing)
#     @test !is_error(completeResult1)
#     if !is_error(completeResult1)
#         @test unwrap(completeResult1) === false
#     end

#     # Second call should increment
#     completeResult2 = splitcomplete(defaultParser, nothing)
#     @test !is_error(completeResult2)
#     if !is_error(completeResult2)
#         @test unwrap(completeResult2) === true
#     end
# end

@testset "should propagate successful parse results correctly" begin
    baseParser = option(("--name", "-n"), str())
    defaultParser = withDefault(baseParser, "anonymous")

    buffer = ["-n", "Alice"]
    state = defaultParser.initialState
    ctx = Context(buffer, state)

    parseResult = splitparse(defaultParser, ctx)
    @test !is_error(parseResult)
    if !is_error(parseResult)
        ps = unwrap(parseResult)
        @test ps.next.buffer == String[]
        @test ps.consumed == ("-n", "Alice")

        completeResult = splitcomplete(defaultParser, ps.next.state)
        @test !is_error(completeResult)
        if !is_error(completeResult)
            @test unwrap(completeResult) == "Alice"
        end
    end
end

@testset "should propagate failed parse results correctly" begin
    baseParser = flag("-v", "--verbose")
    defaultParser = withDefault(baseParser, false)

    buffer = ["--help"]
    state = defaultParser.initialState
    ctx = Context(buffer, state)

    parseResult = splitparse(defaultParser, ctx)
    @test is_error(parseResult)
    if is_error(parseResult)
        pf = unwrap_error(parseResult)
        @test pf.consumed == 0
        @test occursin("No Matched", string(pf.error))
    end
end

@testset "should work in object combinations - main use case" begin
    parser = object(
        (
            verbose = flag("-v", "--verbose"),
            port = (withDefault(8080) ∘ option)(("--port", "-p"), integer()),
            host = (withDefault("localhost") ∘ option)(("--host", "-h"), str()),
        )
    )

    # Defaults case
    argv_defaults = ["-v"]
    ctx_defaults = Context(argv_defaults, parser.initialState)
    res_defaults = splitparse(parser, ctx_defaults)
    @test !is_error(res_defaults)
    if !is_error(res_defaults)
        st = unwrap(res_defaults).next.state
        @test (@? getfield(st, :verbose)) == true
        @test (@? getfield(st, :port)) == 8080
        @test (@? getfield(st, :host)) == "localhost"
    end

    # Provided values case
    argv_values = ["-v", "-p", "3000", "-h", "example.com"]
    ctx_values = Context(argv_values, parser.initialState)
    res_values = splitparse(parser, ctx_values)
    @test !is_error(res_values)
    if !is_error(res_values)
        st = unwrap(res_values).next.state
        @test (@? getfield(st, :verbose)) == true
        @test (@? getfield(st, :port)) == 3000
        @test (@? getfield(st, :host)) == "example.com"
    end
end

@testset "should work with constant parsers" begin
    baseParser = @constant(:hello)
    defaultParser = withDefault(baseParser, :default)

    buffer = String[]
    state = defaultParser.initialState
    ctx = Context(buffer, state)

    parseResult = splitparse(defaultParser, ctx)
    @test !is_error(parseResult)
    if !is_error(parseResult)
        next_state = unwrap(parseResult).next.state
        completeResult = splitcomplete(defaultParser, next_state)
        @test !is_error(completeResult)
        if !is_error(completeResult)
            @test unwrap(completeResult) == :hello
        end
    end
end

@testset "should work with different value types" begin
    stringParser = withDefault(option("-s", str()), "default-string")
    numberParser = withDefault(option("-n", integer()), 42)
    booleanParser = withDefault(flag("-b"), true)
    arrayParser = withDefault(@constant((1, 2, 3)), (3, 2, 1))

    # Test string default
    stringResult = splitcomplete(stringParser, none(tstate(stringParser.parser)))
    @test !is_error(stringResult)
    if !is_error(stringResult)
        @test unwrap(stringResult) == "default-string"
    end

    # Test number default
    numberResult = splitcomplete(numberParser, none(tstate(numberParser.parser)))
    @test !is_error(numberResult)
    if !is_error(numberResult)
        @test unwrap(numberResult) == 42
    end

    # Test boolean default
    booleanResult = splitcomplete(booleanParser, none(tstate(booleanParser.parser)))
    @test !is_error(booleanResult)
    if !is_error(booleanResult)
        @test unwrap(booleanResult) == true
    end

    # Test array default (returns constant value, not default when parser succeeds)
    # When manually feeding a completion state, mirror it with Vector{Result}
    arrayResult = splitcomplete(arrayParser, some(Val((1, 2, 3))))
    @test !is_error(arrayResult)
    if !is_error(arrayResult)
        @test unwrap(arrayResult) == (1, 2, 3)
    end
end

@testset "should propagate wrapped parser completion failures" begin
    baseParser = option(("--port", "-p"), integer(; min = 1))
    defaultParser = withDefault(baseParser, 8080)

    # Manually feed a failing completion state from the wrapped parser
    err::Result{tval(baseParser), String} = Err("Port must be >= 1")
    completeResult = splitcomplete(defaultParser, some(err))
    @test is_error(completeResult)
    if is_error(completeResult)
        @test occursin("Port must be >= 1", string(unwrap_error(completeResult)))
    end
end

@testset "should handle state transitions correctly" begin
    baseParser = option(("-n", "--name"), str())
    defaultParser = withDefault(baseParser, "anonymous")

    # Test with undefined initial state
    @test defaultParser.initialState === none(tstate(baseParser))

    # Test state wrapping during successful parse
    buffer = ["-n", "test"]
    ctx = Context(buffer, none(tstate(baseParser)))
    parseResult = splitparse(defaultParser, ctx)

    @test !is_error(parseResult)
    if !is_error(parseResult)
        ps = unwrap(parseResult)
        st = ps.next.state
        @test !is_error(st)
        if !is_error(st)
            @test unwrap(unwrap(st)) == "test"
        end
    end
end

@testset "should work with argument parsers in object context" begin
    parser = object(
        (
            verbose = flag("-v", "--verbose"),
            file = withDefault(argument(str(; metavar = "FILE")), "input.txt"),
        )
    )

    res1 = argparse(parser, ["-v", "custom.txt"])
    @test !is_error(res1)
    if !is_error(res1)
        st = unwrap(res1)
        @test getproperty(st, :verbose) == true
        @test getproperty(st, :file) == "custom.txt"
    end


    res2 = argparse(parser, ["-v"])
    @test !is_error(res2)
    if !is_error(res2)
        st = unwrap(res2)
        @test getproperty(st, :verbose) == true
        @test getproperty(st, :file) == "input.txt"
    end
end

@testset "should work in complex combinations with validation" begin
    parser = object(
        (
            command = option(("-c", "--command"), str()),
            port = withDefault(option(("-p", "--port"), integer(; min = 1024, max = 0xffff)), 8080),
            debug = withDefault(flag("-d", "--debug"), false),
        )
    )

    validResult = argparse(parser, ["-c", "start", "-p", "3000", "-d"])
    @test !is_error(validResult)
    if !is_error(validResult)
        st = unwrap(validResult)
        @test getproperty(st, :command) == "start"
        @test getproperty(st, :port) == 3000
        @test getproperty(st, :debug) == true
    end

    defaultResult = argparse(parser, ["-c", "start"])
    @test !is_error(defaultResult)
    if !is_error(defaultResult)
        st = unwrap(defaultResult)
        @test getproperty(st, :command) == "start"
        @test getproperty(st, :port) == 8080
        @test getproperty(st, :debug) == false
    end
end

@testset "should be type stable" begin
    @test_opt withDefault(option(("-p", "--port"), integer(; min = 1024, max = 0xffff)), 8080)
    @test_opt withDefault(flag("-d", "--debug"), false)

    @test_opt object(
        (
            command = option(("-c", "--command"), str()),
            port = withDefault(option(("-p", "--port"), integer(; min = 1024, max = 0xffff)), 8080),
            debug = withDefault(flag("-d", "--debug"), false),
        )
    )

    parser = object(
        (
            port = option(("-p", "--port"), integer(; min = 1024, max = 0xffff)),
            command = option(("-c", "--command"), str()),
            debug = flag("-d", "--debug"),
        )
    )

    @test_opt parse(unwrapunion(parser), Context(["-c", "start", "-p", "3000", "-d"], parser.initialState))


    @test_opt argparse(parser, ["-c", "start", "-p", "3000", "-d"])
end
