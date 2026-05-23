@testset "should create a parser with same priority as wrapped parser" begin
    baseParser = switch("-v", "--verbose")
    defaultParser = default(baseParser, false)

    @test priority(defaultParser) == priority(baseParser)
    @test defaultParser.initialState === none(tstate(baseParser))
end

@testset "should return wrapped parser value when it succeeds" begin
    baseParser = switch("-v", "--verbose")
    defaultParser = default(baseParser, false)

    buffer = ["-v"]
    state = defaultParser.initialState
    ctx = mkctx(buffer, state)

    parseResult = splitparse(defaultParser, ctx)
    @test !is_error(parseResult)
    next_state = res_nextstate(unwrap(parseResult))
    completeResult = splitcomplete(defaultParser, next_state)
    @test !is_error(completeResult)
    @test unwrap(completeResult) === true
end

@testset "should return default value when parser doesn't match" begin
    baseParser = switch("-v", "--verbose")
    defaultValue = false
    defaultParser = default(baseParser, defaultValue)

    completeResult = splitcomplete(defaultParser, none(tstate(baseParser)))
    @test !is_error(completeResult)
    @test unwrap(completeResult) === defaultValue
end

# @testset "should work with function-based default values" begin
#     call_count = Ref(0)
#     defaultFunction = () -> begin
#         call_count[] += 1
#         call_count[] > 1
#     end

#     baseParser = switch("-v", "--verbose")
#     defaultParser = default(baseParser, defaultFunction)

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
    defaultParser = default(baseParser, "anonymous")

    buffer = ["-n", "Alice"]
    state = defaultParser.initialState
    ctx = mkctx(buffer, state)

    parseResult = splitparse(defaultParser, ctx)
    @test !is_error(parseResult)
    ps = unwrap(parseResult)
    @test ctx_remaining(res_nextctx(ps)) == String[]
    @test as_tuple(res_consumed(ps)) == ("-n", "Alice")

    completeResult = splitcomplete(defaultParser, res_nextstate(ps))
    @test !is_error(completeResult)
    @test unwrap(completeResult) == "Alice"
end

@testset "should return success with empty consumed when inner parser fails without consuming." begin
    baseParser = switch("-v", "--verbose")
    defaultParser = default(baseParser, false)

    buffer = ["--help"]
    state = defaultParser.initialState
    ctx = mkctx(buffer, state)

    parseResult = splitparse(defaultParser, ctx)

    # when inner parser fails without consuming input, optional returns success

    @test !is_error(parseResult)
    pf = unwrap(parseResult)
    @test length(res_consumed(pf)) == 0
    @test ctx_remaining(res_nextctx(pf)) == ["--help"]
end

@testset "should work in record combinations - main use case" begin
    parser = record(
        (
            verbose = switch("-v", "--verbose"),
            port = (default(8080) ∘ option)(("--port", "-p"), integer()),
            host = (default("localhost") ∘ option)(("--host", "-h"), str()),
        )
    )

    # Defaults case
    argv_defaults = ["-v"]
    ctx_defaults = mkctx(argv_defaults, parser.initialState)
    res_defaults = splitparse(parser, ctx_defaults)
    @test !is_error(res_defaults)
    if !is_error(res_defaults)
        st = res_nextstate(unwrap(res_defaults))
        @test (@? getfield(st, :verbose)) == true
        @test (@? getfield(st, :port)) == 8080
        @test (@? getfield(st, :host)) == "localhost"
    end

    # Provided values case
    argv_values = ["-v", "-p", "3000", "-h", "example.com"]
    ctx_values = mkctx(argv_values, parser.initialState)
    res_values = splitparse(parser, ctx_values)
    @test !is_error(res_values)
    if !is_error(res_values)
        st = res_nextstate(unwrap(res_values))
        @test (@? getfield(st, :verbose)) == true
        @test (@? getfield(st, :port)) == 3000
        @test (@? getfield(st, :host)) == "example.com"
    end
end

@testset "should work with constant parsers" begin
    baseParser = @constant(:hello)
    defaultParser = default(baseParser, Val(:hello))

    buffer = String[]
    state = defaultParser.initialState
    ctx = mkctx(buffer, state)

    parseResult = splitparse(defaultParser, ctx)
    @test !is_error(parseResult)
    next_state = res_nextstate(unwrap(parseResult))
    completeResult = splitcomplete(defaultParser, next_state)
    @test !is_error(completeResult)
    @test unwrap(completeResult) == Val(:hello)
end

@testset "should work with different value types" begin
    stringParser = default(option("-s", str()), "default-string")
    numberParser = default(option("-n", integer()), 42)
    booleanParser = default(switch("-b"), true)
    arrayParser = default(@constant((1, 2, 3)), Val((1, 2, 3)))

    # Test string default
    stringResult = splitcomplete(stringParser, none(tstate(stringParser.parser)))
    @test !is_error(stringResult)
    @test unwrap(stringResult) == "default-string"

    # Test number default
    numberResult = splitcomplete(numberParser, none(tstate(numberParser.parser)))
    @test !is_error(numberResult)
    @test unwrap(numberResult) == 42

    # Test boolean default
    booleanResult = splitcomplete(booleanParser, none(tstate(booleanParser.parser)))
    @test !is_error(booleanResult)
    @test unwrap(booleanResult) == true

    # Test array default (returns constant value, not default when parser succeeds)
    # When manually feeding a completion state, mirror it with Vector{Result}
    arrayResult = splitcomplete(arrayParser, some(Val((1, 2, 3))))
    @test !is_error(arrayResult)
    @test unwrap(arrayResult) == Val((1, 2, 3))
end

@testset "should return error when the inner state fails to validate the matched input." begin
    baseParser = option(("--port", "-p"), integer(; min = 100))
    defaultParser = default(baseParser, 8080)

    err = parse_fail(defaultParser, ["-p", "10"])
    @test err isa OptParse.IntegerValError
    @test err.code == OptParse.INTEGER_BelowMin
end

@testset "should handle state transitions correctly" begin
    baseParser = option(("-n", "--name"), str())
    defaultParser = default(baseParser, "anonymous")

    # Test with undefined initial state
    @test defaultParser.initialState === none(tstate(baseParser))

    # Test state wrapping during successful parse
    buffer = ["-n", "test"]
    ctx = mkctx(buffer, none(tstate(baseParser)))
    parseResult = splitparse(defaultParser, ctx)

    @test !is_error(parseResult)
    ps = unwrap(parseResult)
    st = res_nextstate(ps)
    @test !is_error(st)
    @test unwrap(unwrap(st)) == "test"
end

@testset "should work with argument parsers in record context" begin
    parser = record(
        (
            verbose = switch("-v", "--verbose"),
            file = default(arg(str(; metavar = "FILE")), "input.txt"),
        )
    )

    st = parse_ok(parser, ["-v", "custom.txt"])
    @test getproperty(st, :verbose) == true
    @test getproperty(st, :file) == "custom.txt"


    st = parse_ok(parser, ["-v"])
    @test getproperty(st, :verbose) == true
    @test getproperty(st, :file) == "input.txt"
end

@testset "should work in complex combinations with validation" begin
    parser = record(
        (
            command = option(("-c", "--command"), str()),
            port = default(option(("-p", "--port"), integer(; min = 1024, max = 0xffff)), 8080),
            debug = default(switch("-d", "--debug"), false),
        )
    )

    st = parse_ok(parser, ["-c", "start", "-p", "3000", "-d"])
    @test getproperty(st, :command) == "start"
    @test getproperty(st, :port) == 3000
    @test getproperty(st, :debug) == true

    st = parse_ok(parser, ["-c", "start"])
    @test getproperty(st, :command) == "start"
    @test getproperty(st, :port) == 8080
    @test getproperty(st, :debug) == false
end


@testset "should return default value when parsing empty input" begin
    parser = default(option("-n", "--name", str()), "Bob")

    @test parse_ok(parser, String[]) == "Bob"

    defflag = default(switch("-v"), false)
    @test parse_ok(defflag, String[]) == false
end

@testset "should propagate errors when inner parser partially consumes input" begin
    optionalopt = default(option("-n", str()), "Bob")

    err = parse_fail(optionalopt, ["-n"])
    @test err isa OptParse.ArgOptionError
    @test err.code == OptParse.OPTION_MissingValue
end

@testset "should correctly handle -- edge cases" begin
    def = default(option("-n", "--name", str()), "bob")

    err = parse_fail(def, ["--", "-n", "alice"])
    @test err isa OptParse.MainError

    err = parse_fail(def, ["-n", "--"])
    @test err isa OptParse.ArgOptionError
    @test err.code == OptParse.OPTION_MissingValue

    @test parse_ok(def, ["--"]) == "bob"

    # should also correctly propagate the side effects properly optionsTerminated state.
    ctx = mkctx(["--", "arg"], def.initialState)
    pres = splitparse(def, ctx)
    @test !is_error(pres)
    pok = unwrap(pres)
    @test as_tuple(res_consumed(pok)) == ("--",)
    @test ctx_optterm(res_nextctx(pok)) == true
    @test ctx_remaining(res_nextctx(pok)) == ["arg"]

end


@testset "should be type stable" begin
    @test_opt default(option(("-p", "--port"), integer(; min = 1024, max = 0xffff)), 8080)
    @test_opt default(switch("-d", "--debug"), false)

    @test_opt record(
        (
            command = option(("-c", "--command"), str()),
            port = default(option(("-p", "--port"), integer(; min = 1024, max = 0xffff)), 8080),
            debug = default(switch("-d", "--debug"), false),
        )
    )

    parser = record(
        (
            port = option(("-p", "--port"), integer(; min = 1024, max = 0xffff)),
            command = option(("-c", "--command"), str()),
            debug = switch("-d", "--debug"),
        )
    )
end
