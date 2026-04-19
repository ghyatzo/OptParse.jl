@testset "should create a parser with same priority as wrapped parser" begin
    baseParser = option(("-l", "--locale"), str())
    multipleParser = multiple(baseParser)

    @test priority(multipleParser) == priority(baseParser)
    @test multipleParser.initialState == tval(baseParser)[]
end

@testset "should parse multiple occurrences of wrapped parser" begin
    baseParser = option(("-l", "--locale"), str())
    multipleParser = multiple(baseParser)

    # Test all combinations of option forms. Cf. issue #2.
    for opt1 in (["-l", "en"], ["--locale", "en"], ["--locale=en"]),
        opt2 in (["-l", "fr"], ["--locale", "fr"], ["--locale=fr"]),
        opt3 in (["-l", "de"], ["--locale", "de"], ["--locale=de"])

        val = parse_ok(multipleParser, [opt1; opt2; opt3])
        @test val == ["en", "fr", "de"]
    end
end

@testset "should return empty array when no matches found in object context" begin
    parser = object(
        (
            locales = multiple(option(("-l", "--locale"), str())),
            verbose = gate("-v", "--verbose"),
        )
    )

    val = parse_ok(parser, ["-v"])
    @test val.locales == []
    @test val.verbose == true
end

@testset "should work with argument parsers" begin
    baseParser = arg(str())
    multipleParser = multiple(baseParser)

    val = parse_ok(multipleParser, ["file1.txt", "file2.txt", "file3.txt"])
    @test val == ["file1.txt", "file2.txt", "file3.txt"]
end

@testset "should not count control-only consuming matches as repetitions" begin
    parser = multiple(gate("-a"); min = 1)

    # `--` is consumed only to propagate option termination.
    # It must not count as satisfying the minimum repetition count.
    err = parse_fail(parser, ["--"])
    @test err.domain == OptParse.ERR_ModMultiple
    @test OptParse.MultipleErrCode(err.code) == OptParse.MULTIPLE_TooFew
end

@testset "should keep parsing positional repetitions after --" begin
    parser = multiple(arg(str()); min = 1)

    val = parse_ok(parser, ["--", "hello", "world"])
    @test val == ["hello", "world"]
end

@testset "should enforce minimum constraint" begin
    baseParser = option(("-l", "--locale"), str())
    multipleParser = multiple(baseParser; min = 2)

    err1 = parse_fail(multipleParser, ["-l", "en"])
    @test err1.domain == OptParse.ERR_ModMultiple
    @test OptParse.MultipleErrCode(err1.code) == OptParse.MULTIPLE_TooFew

    val = parse_ok(multipleParser, ["-l", "en", "-l", "fr"])
    @test val == ["en", "fr"]
end

@testset "should enforce maximum constraint" begin
    baseParser = arg(str())
    multipleParser = multiple(baseParser; max = 2)

    err = parse_fail(multipleParser, ["file1.txt", "file2.txt", "file3.txt"])
    @test err.domain == OptParse.ERR_ModMultiple
    @test OptParse.MultipleErrCode(err.code) == OptParse.MULTIPLE_TooMany

    val = parse_ok(multipleParser, ["file1.txt", "file2.txt"])
    @test val == ["file1.txt", "file2.txt"]
end

@testset "should enforce both min and max constraints" begin
    baseParser = arg(str())
    multipleParser = multiple(baseParser; min = 1, max = 3)

    # When used standalone, multiple() fails if it can't parse at least one occurrence
    err = parse_fail(multipleParser, String[])
    @test err.domain == OptParse.ERR_ArgArgument
    @test OptParse.ArgumentErrCode(err.code) == OptParse.ARGUMENT_EndOfInput

    err = parse_fail(multipleParser, ["a", "b", "c", "d"])
    @test err.domain == OptParse.ERR_ModMultiple
    @test OptParse.MultipleErrCode(err.code) == OptParse.MULTIPLE_TooMany

    val = parse_ok(multipleParser, ["a", "b"])
    @test val == ["a", "b"]
end

@testset "should work with default options (min=0, max=Infinity)" begin
    parser = object(
        (
            options = multiple(option("-x", str())),
            help = gate("-h", "--help"),
        )
    )

    # When min=0, should allow empty array in object context
    resEmpty = parse_ok(parser, ["-h"])
    valEmpty = resEmpty
    @test valEmpty.options == []
    @test valEmpty.help == true

    # Test with many values to ensure no arbitrary limit
    manyArgs = String[]
    for i in 0:9
        append!(manyArgs, ["-x", "value$(i)"])
    end
    push!(manyArgs, "-h")

    valMany = parse_ok(parser, manyArgs)
    @test length(valMany.options) == 10
    @test valMany.options[1] == "value0"
    @test valMany.options[10] == "value9"
    @test valMany.help == true
end

@testset "should work in object combinations" begin
    parser = object(
        (
            locales = multiple(option(("-l", "--locale"), str())),
            verbose = gate("-v", "--verbose"),
            files = multiple(arg(str()); min = 1),
        )
    )

    val = parse_ok(parser, ["-l", "en", "-l", "fr", "-v", "file1.txt", "file2.txt"])
    @test val.locales == ["en", "fr"]
    @test val.verbose == true
    @test val.files == ["file1.txt", "file2.txt"]
end

@testset "should propagate wrapped parser failures" begin
    baseParser = option(("-p", "--port"), integer(; min = 1, max = 0xffff))
    multipleParser = multiple(baseParser)

    err = parse_fail(multipleParser, ["-p", "8080", "-p", "invalid"])
    # The failure should come from the invalid integer parsing
    @test err.domain == OptParse.ERR_IntegerVal
    @test OptParse.IntegerErrCode(err.code) == OptParse.INTEGER_Invalid
end

@testset "should handle mixed successful and failed parsing attempts in object context" begin
    parser = object(
        (
            numbers = multiple(option("-n", "--number", integer())),
            other = option("--other", str()),
        )
    )

    val = parse_ok(parser, ["-n", "42", "-n", "100", "--other", "value"])
    @test val.numbers == [42, 100]
    @test val.other == "value"
end

@testset "should work with boolean flag options" begin
    baseParser = gate("-v", "--verbose")
    multipleParser = multiple(baseParser)

    val = parse_ok(multipleParser, ["-v", "-v", "-v"])
    @test val == [true, true, true]
end

@testset "should handle parse context state management correctly" begin
    baseParser = option(("-l", "--locale"), str())
    multipleParser = multiple(baseParser)

    state = multipleParser.initialState
    ctx1 = Context(buffer=["-l", "en", "-l", "fr"], state=state)

    parseRes1 = splitparse(multipleParser, ctx1)
    @test !is_error(parseRes1)
    succ1 = unwrap(parseRes1)

    @test as_tuple(ℒ_consumed(succ1)) == ("-l", "en")
    @test length(ℒ_nextstate(succ1)) == 1

    # Parse next occurrence with updated buffer and carried state
    nextState1 = ℒ_nextstate(succ1)
    ctx2 = Context(buffer=["-l", "fr"], state=nextState1)

    parseRes2 = splitparse(multipleParser, ctx2)
    @test !is_error(parseRes2)
    succ2 = unwrap(parseRes2)

    @test as_tuple(ℒ_consumed(succ2)) == ("-l", "fr")
    @test length(ℒ_nextstate(succ2)) == 2
end

@testset "should complete with proper value array" begin
    baseParser = option("-n", "--number", integer())
    multipleParser = multiple(baseParser)


    mockStates = OptParse.ParseResult{Int}[Ok(42), Ok(100), Ok(7)]
    comp = splitcomplete(multipleParser, mockStates)
    @test !is_error(comp)
    @test unwrap(comp) == [42, 100, 7]
end

@testset "should fail completion if wrapped parser completion fails" begin
    baseParser = option("-n", "--number", integer())
    multipleParser = multiple(baseParser)

    mockStates = OptParse.ParseResult{Int}[Ok(42), Err(OptParse.integerval_error(OptParse.INTEGER_Invalid)), Ok(7)]
    comp = splitcomplete(multipleParser, mockStates)
    @test is_error(comp)
    err = unwrap_error(comp)
    @test err.domain == OptParse.ERR_IntegerVal
end

@testset "should handle empty state array with min constraint" begin
    baseParser = option(("-l", "--locale"), str())
    multipleParser = multiple(baseParser; min = 1)

    comp = splitcomplete(multipleParser, OptParse.ParseResult{String}[])
    @test is_error(comp)
    err = unwrap_error(comp)
    @test err.domain == OptParse.ERR_ModMultiple
    @test OptParse.MultipleErrCode(err.code) == OptParse.MULTIPLE_TooFew
end

@testset "should handle max constraint at completion" begin
    baseParser = option(("-l", "--locale"), str())
    multipleParser = multiple(baseParser; max = 2)

    mockStates = OptParse.ParseResult{String}[Ok("en"), Ok("fr"), Ok("de")]
    comp = splitcomplete(multipleParser, mockStates)
    @test is_error(comp)
    err = unwrap_error(comp)
    @test err.domain == OptParse.ERR_ModMultiple
    @test OptParse.MultipleErrCode(err.code) == OptParse.MULTIPLE_TooMany
end

@testset "should work with constant parsers" begin
    baseParser = @constant(:fixed)
    multipleParser = multiple(baseParser; min = 1, max = 3)

    # Since constant parser does not consume input, implementation should avoid infinite loops
    val = parse_ok(multipleParser, String[])
    @test val == [Val(:fixed)]
end

@testset "should reproduce example usage patterns" begin
    # Example 1
    parser1 = object(
        (
            name = option("-n", "--name", str()),
            locales = multiple(option(("-l", "--locale"), str())),
            id = arg(str()),
        )
    )
    val1 = parse_ok(parser1, ["-n", "John", "-l", "en-US", "-l", "fr-FR", "user123"])
    @test val1.name == "John"
    @test val1.locales == ["en-US", "fr-FR"]
    @test val1.id == "user123"

    # Example 2: constrained multiple arguments
    parser2 = object(
        (
            title = option("-t", "--title", str()),
            ids = multiple(arg(str()); min = 1, max = 3),
        )
    )
    val2 = parse_ok(parser2, ["-t", "My Title", "id1", "id2"])
    @test val2.title == "My Title"
    @test val2.ids == ["id1", "id2"]

    # Constraint violation
    err = parse_fail(parser2, ["-t", "Title", "id1", "id2", "id3", "id4"])
    @test err.domain == OptParse.ERR_ModMultiple
    @test OptParse.MultipleErrCode(err.code) == OptParse.MULTIPLE_TooMany
end

@testset "should handle options terminator correctly" begin
    parser = object(
        (
            locales = multiple(option(("-l", "--locale"), str())),
            args = multiple(arg(str())),
        )
    )

    val = parse_ok(parser, ["-l", "en", "--", "-l", "fr"])
    @test val.locales == ["en"]
    @test val.args == ["-l", "fr"]
end

@testset "should handle state transitions and updates correctly" begin
    baseParser = arg(str())
    multipleParser = multiple(baseParser)

    # Test initial state
    @test multipleParser.initialState == tval(baseParser)[]

    ctx1 = Context(buffer=["arg1"], state=multipleParser.initialState)
    parseRes1 = splitparse(multipleParser, ctx1)
    @test !is_error(parseRes1)
    succ1 = unwrap(parseRes1)
    @test length(ℒ_state(succ1.next)) == 1
    @test as_tuple(ℒ_consumed(succ1)) == ("arg1",)

    # Next context with carried state but new buffer
    carried = ℒ_state(succ1.next)
    ctx2 = widen_state(tstate(multipleParser), Context(buffer=["arg2"], state=carried))
    parseRes2 = @unionsplit  parse(multipleParser, ctx2)
    @test !is_error(parseRes2)
    succ2 = unwrap(parseRes2)
    @test length(ℒ_state(succ2.next)) == 2
    @test as_tuple(ℒ_consumed(succ2)) == ("arg2",)
end

@testset "should work with complex value parsers" begin
    baseParser = option(("-p", "--port"), integer(; min = 1024, max = 0xffff))
    multipleParser = multiple(baseParser; min = 1, max = 5)

    validVals = parse_ok(multipleParser, ["-p", "8080", "-p", "9000", "-p", "3000"])
    @test validVals == [8080, 9000, 3000]

    invalidErr = parse_fail(multipleParser, ["-p", "8080", "-p", "100"])
    @test invalidErr.domain == OptParse.ERR_IntegerVal  # Should fail due to port 100 being below minimum

    tooManyErr = parse_fail(multipleParser, ["-p", "8080", "-p", "9000", "-p", "3000", "-p", "4000", "-p", "5000", "-p", "6000"])
    @test tooManyErr.domain == OptParse.ERR_ModMultiple
    @test OptParse.MultipleErrCode(tooManyErr.code) == OptParse.MULTIPLE_TooMany
end

@testset "should maintain type safety with different value types" begin
    stringMultiple = multiple(option("-s", str()))
    integerMultiple = multiple(option("-i", integer()))
    booleanMultiple = multiple(gate("-b"))

    # Strings
    sVals = parse_ok(stringMultiple, ["-s", "hello", "-s", "world"])
    @test length(sVals) == 2
    @test sVals[1] isa String
    @test sVals == ["hello", "world"]

    # Integers
    iVals = parse_ok(integerMultiple, ["-i", "42", "-i", "100"])
    @test length(iVals) == 2
    @test iVals[1] isa Int
    @test iVals == [42, 100]

    # Booleans
    bVals = parse_ok(booleanMultiple, ["-bb"])
    @test length(bVals) == 2
    @test bVals[1] isa Bool
    @test bVals == [true, true]
end
