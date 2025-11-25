@testset "should create a parser with same priority as wrapped parser" begin
    baseParser = flag("-v", "--verbose")
    optionalParser = optional(baseParser)

    @test priority(optionalParser) == priority(baseParser)
    # @test optionalParser.initialState === nothing
    @test optionalParser.initialState === none(tstate(baseParser))
end

@testset "should return wrapped parser value when it succeeds" begin
    baseParser = flag("-v", "--verbose")
    optionalParser = optional(baseParser)

    context = Context(["-v"], optionalParser.initialState)
    parseResult = splitparse(optionalParser, context)

    @test !is_error(parseResult)
    ps = unwrap(parseResult)

    # Completing the optional with the state produced by parse
    completeResult = splitcomplete(optionalParser, ps.next.state)
    @test !is_error(completeResult)
    @test unwrap(completeResult) == true
end

@testset "should propagate successful parse results" begin
    baseParser = option(("-n", "--name"), str())
    optionalParser = optional(baseParser)

    context = Context(["-n", "Alice"], optionalParser.initialState)
    parseResult = splitparse(optionalParser, context)

    @test !is_error(parseResult)
    ps = unwrap(parseResult)

    @test ps.next.buffer == String[]
    @test ps.consumed == ("-n", "Alice")

    # # optional keeps a collection of inner states
    # @test ps.next.state isa AbstractVector
    # @test length(ps.next.state) == 1
end

@testset "should propagate failed parse results" begin
    baseParser = flag("-v", "--verbose")
    optionalParser = optional(baseParser)

    context = Context(["--help"], optionalParser.initialState)
    parseResult = splitparse(optionalParser, context)

    @test is_error(parseResult)
    # pf = unwrap_error(parseResult)

    # @test pf.consumed == 0
    # @test occursin("No matched option", string(pf.error))
end

@testset "should complete with undefined when internal state is undefined" begin
    baseParser = flag("-v", "--verbose")
    optionalParser = optional(baseParser)

    completeResult = splitcomplete(optionalParser, none(tstate(baseParser)))

    @test !is_error(completeResult)
    @test unwrap(completeResult) === nothing
end

@testset "should complete with wrapped parser result when state is defined" begin
    baseParser = flag("-v", "--verbose")
    optionalParser = optional(baseParser)

    # Simulate a collected successful inner state (as optional.parse would)
    successfulState = some(Result{Bool, String}(Ok(true)))
    completeResult = splitcomplete(optionalParser, successfulState)

    @test !is_error(completeResult)
    @test unwrap(completeResult) == true
end

@testset "should propagate wrapped parser completion failures" begin
    baseParser = option(("-p", "--port"), integer(; min = 1))
    optionalParser = optional(baseParser)

    # Simulate a collected failed inner state
    failedState = some(Result{Int, String}(Err("Port must be >= 1")))
    completeResult = splitcomplete(optionalParser, failedState)

    @test is_error(completeResult)
    @test occursin("Port must be >= 1", string(unwrap_error(completeResult)))
end

@testset "should work in object combinations - main use case" begin
    obj = object(
        (
            verbose = flag("-v", "--verbose"),
            port = (optional ∘ option)(("-p", "--port"), integer()),
            output = (optional ∘ option)(("-o", "--output"), str()),
        )
    )

    ctx = Context(["-v", "-p", "8080"], obj.initialState)
    resultWithOptional = splitparse(obj, ctx)
    @test !is_error(resultWithOptional)
    val = unwrap(resultWithOptional)

    completeResult = splitcomplete(obj, val.next.state)
    @test !is_error(completeResult)
    val = unwrap(completeResult)
    @test val.verbose == true
    @test val.port == 8080
    @test val.output === nothing

    ctx = Context(["-v"], obj.initialState)
    resultWithoutOptional = splitparse(obj, ctx)
    @test !is_error(resultWithoutOptional)
    val2 = unwrap(resultWithoutOptional)

    completeResult = splitcomplete(obj, val2.next.state)
    @test !is_error(completeResult)
    val2 = unwrap(completeResult)

    @test val2.verbose == true
    @test val2.port === nothing
    @test val2.output === nothing
end

@testset "should work with constant parsers" begin
    baseParser = @constant(:hello)
    optionalParser = optional(baseParser)

    context = Context(String[], optionalParser.initialState)
    parseResult = splitparse(optionalParser, context)

    @test !is_error(parseResult)
    ps = unwrap(parseResult)

    completeResult = splitcomplete(optionalParser, ps.next.state)
    @test !is_error(completeResult)
    @test unwrap(completeResult) == :hello
end

@testset "should handle options terminator" begin
    baseParser = flag("-v", "--verbose")
    optionalParser = optional(baseParser)

    context = Context(["-v"], optionalParser.initialState)
    context = Context{typeof(context.state)}(context.buffer, context.state, true)  # optionsTerminated=true

    parseResult = splitparse(optionalParser, context)
    @test is_error(parseResult)
    pf = unwrap_error(parseResult)

    @test pf.consumed == 0
    @test occursin("No more options", string(pf.error))
end

@testset "should work with bundled short options through wrapped parser" begin
    baseParser = flag("-v")
    optionalParser = optional(baseParser)

    context = Context(["-vd"], optionalParser.initialState)
    parseResult = splitparse(optionalParser, context)

    @test !is_error(parseResult)
    ps = unwrap(parseResult)

    @test ps.next.buffer == ["-d"]
    @test ps.consumed == ("-v",)

    completeResult = splitcomplete(optionalParser, ps.next.state)
    @test !is_error(completeResult)
    @test unwrap(completeResult) == true
end

@testset "should handle state transitions" begin
    baseParser = option(("-n", "--name"), str())
    optionalParser = optional(baseParser)

    # initial state should be "undefined" (nothing)
    @test optionalParser.initialState === none(tstate(baseParser))

    context = Context(["-n", "test"], none(tstate(baseParser)))
    parseResult = splitparse(optionalParser, context)

    @test !is_error(parseResult)
    ps = unwrap(parseResult)

    # @test ps.next.state isa AbstractVector
    # @test length(ps.next.state) == 1

    inner = ps.next.state
    @test inner isa Option
    innerres = @something base(inner)
    @test !is_error(innerres)
    @test unwrap(innerres) == "test"
end

@testset "should be type stable" begin
    baseParser = option(("-n", "--name"), str())
    @test_opt optional(baseParser)
    optionalParser = optional(baseParser)

    # initial state should be "undefined" (nothing)
    @test optionalParser.initialState === none(tstate(baseParser))

    context = Context(["-n", "test"], none(tstate(baseParser)))

    @test_opt parse(unwrapunion(optionalParser), context)
    res = parse(unwrapunion(optionalParser), context)

    @test_opt complete(unwrapunion(optionalParser), unwrap(res).next.state)
end
