@testset "should create a parser with same priority as wrapped parser" begin
    baseParser = option(("-l", "--locale"), str())
    repeatedParser = many(baseParser)

    @test priority(repeatedParser) == priority(baseParser)
    @test repeatedParser.initialState == tval(baseParser)[]
end

@testset "should parse repeated occurrences of wrapped parser" begin
    baseParser = option(("-l", "--locale"), str())
    repeatedParser = many(baseParser)

    # Test all combinations of option forms. Cf. issue #2.
    for opt1 in (["-l", "en"], ["--locale", "en"], ["--locale=en"]),
            opt2 in (["-l", "fr"], ["--locale", "fr"], ["--locale=fr"]),
            opt3 in (["-l", "de"], ["--locale", "de"], ["--locale=de"])

        val = parse_ok(repeatedParser, [opt1; opt2; opt3])
        @test val == ["en", "fr", "de"]
    end
end

@testset "should return empty array when no matches found in record context" begin
    parser = record(
        (
            locales = many(option(("-l", "--locale"), str())),
            verbose = switch("-v", "--verbose"),
        )
    )

    val = parse_ok(parser, ["-v"])
    @test val.locales == []
    @test val.verbose == true
end

@testset "should work with argument parsers" begin
    baseParser = arg(str())
    repeatedParser = many(baseParser)

    val = parse_ok(repeatedParser, ["file1.txt", "file2.txt", "file3.txt"])
    @test val == ["file1.txt", "file2.txt", "file3.txt"]
end

@testset "should allow zero matches when min=0" begin
    parser = many(arg(str()))

    val = parse_ok(parser, String[])
    @test val == String[]
end

@testset "should not count control-only consuming matches as repetitions" begin
    parser = many1(switch("-a"))

    # `--` is consumed only to propagate option termination.
    # It must not count as satisfying the minimum repetition count.
    err = parse_fail(parser, ["--"])
    @test err isa OptParse.ModMultipleError
    @test err.code == OptParse.MULTIPLE_TooFew
end

@testset "should keep parsing positional repetitions after --" begin
    parser = many1(arg(str()))

    val = parse_ok(parser, ["--", "hello", "world"])
    @test val == ["hello", "world"]
end

@testset "should enforce minimum constraint" begin
    baseParser = option(("-l", "--locale"), str())
    repeatedParser = repeated(baseParser; min = 2)

    err1 = parse_fail(repeatedParser, ["-l", "en"])
    @test err1 isa OptParse.ModMultipleError
    @test err1.code == OptParse.MULTIPLE_TooFew

    val = parse_ok(repeatedParser, ["-l", "en", "-l", "fr"])
    @test val == ["en", "fr"]
end

@testset "should enforce maximum constraint" begin
    baseParser = arg(str())
    repeatedParser = repeated(baseParser; max = 2)

    err = parse_fail(repeatedParser, ["file1.txt", "file2.txt", "file3.txt"])
    @test err isa OptParse.MainError
    @test err.code == OptParse.MAIN_UnexpectedToken

    val = parse_ok(repeatedParser, ["file1.txt", "file2.txt"])
    @test val == ["file1.txt", "file2.txt"]
end

@testset "should enforce both min and max constraints" begin
    baseParser = arg(str())
    repeatedParser = repeated(baseParser; min = 1, max = 3)

    # With `min=1`, an empty input is now a proper `repeated` arity failure.
    err = parse_fail(repeatedParser, String[])
    @test err isa OptParse.ModMultipleError
    @test err.code == OptParse.MULTIPLE_TooFew

    err = parse_fail(repeatedParser, ["a", "b", "c", "d"])
    @test err isa OptParse.MainError
    @test err.code == OptParse.MAIN_UnexpectedToken

    val = parse_ok(repeatedParser, ["a", "b"])
    @test val == ["a", "b"]
end

@testset "should work with default options (min=0, max=Infinity)" begin
    parser = record(
        (
            options = many(option("-x", str())),
            help = switch("-h", "--help"),
        )
    )

    # When min=0, should allow empty array in record context
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

@testset "should work in record combinations" begin
    parser = record(
        (
            locales = many(option(("-l", "--locale"), str())),
            verbose = switch("-v", "--verbose"),
            files = many1(arg(str())),
        )
    )

    val = parse_ok(parser, ["-l", "en", "-l", "fr", "-v", "file1.txt", "file2.txt"])
    @test val.locales == ["en", "fr"]
    @test val.verbose == true
    @test val.files == ["file1.txt", "file2.txt"]
end

@testset "should propagate wrapped parser failures" begin
    baseParser = option(("-p", "--port"), integer(; min = 1, max = 0xffff))
    repeatedParser = many(baseParser)

    err = parse_fail(repeatedParser, ["-p", "8080", "-p", "invalid"])
    # The failure should come from the invalid integer parsing
    @test err isa OptParse.IntegerValError
    @test err.code == OptParse.INTEGER_Invalid
end

@testset "should handle mixed successful and failed parsing attempts in record context" begin
    parser = record(
        (
            numbers = many(option("-n", "--number", integer())),
            other = option("--other", str()),
        )
    )

    val = parse_ok(parser, ["-n", "42", "-n", "100", "--other", "value"])
    @test val.numbers == [42, 100]
    @test val.other == "value"
end

@testset "should delegate to sibling parsers after reaching max" begin
    parser = record(
        (
            files = repeated(arg(str()); max = 2),
            mode = arg(str("MODE")),
        )
    )

    val = parse_ok(parser, ["file1.txt", "file2.txt", "fast"])
    @test val.files == ["file1.txt", "file2.txt"]
    @test val.mode == "fast"
end

@testset "should work with boolean flag options" begin
    baseParser = switch("-v", "--verbose")
    repeatedParser = many(baseParser)

    val = parse_ok(repeatedParser, ["-v", "-v", "-v"])
    @test val == [true, true, true]
end

@testset "should handle parse context state management correctly" begin
    baseParser = option(("-l", "--locale"), str())
    repeatedParser = many(baseParser)

    state = repeatedParser.initialState
    ctx1 = mkctx(["-l", "en", "-l", "fr"], state)

    parseRes1 = splitparse(repeatedParser, ctx1)
    @test !is_error(parseRes1)
    succ1 = unwrap(parseRes1)

    @test as_tuple(res_consumed(succ1)) == ("-l", "en")
    @test length(res_nextstate(succ1)) == 1

    # Parse next occurrence with updated buffer and carried state
    nextState1 = res_nextstate(succ1)
    ctx2 = mkctx(["-l", "fr"], nextState1)

    parseRes2 = splitparse(repeatedParser, ctx2)
    @test !is_error(parseRes2)
    succ2 = unwrap(parseRes2)

    @test as_tuple(res_consumed(succ2)) == ("-l", "fr")
    @test length(res_nextstate(succ2)) == 2
end

@testset "should complete with proper value array" begin
    baseParser = option("-n", "--number", integer())
    repeatedParser = many(baseParser)


    mockStates = OptParse.ParseResult{Int, Union{OptParse.ArgOptionError, OptParse.IntegerValError}}[Ok(42), Ok(100), Ok(7)]
    comp = splitcomplete(repeatedParser, mockStates)
    @test !is_error(comp)
    @test unwrap(comp) == [42, 100, 7]
end

@testset "should fail completion if wrapped parser completion fails" begin
    baseParser = option("-n", "--number", integer())
    repeatedParser = many(baseParser)

    mockStates = OptParse.ParseResult{Int, Union{OptParse.ArgOptionError, OptParse.IntegerValError}}[Ok(42), Err(OptParse.IntegerValError(OptParse.INTEGER_Invalid, "", "")), Ok(7)]
    comp = splitcomplete(repeatedParser, mockStates)
    @test is_error(comp)
    err = unwrap_error(comp)
    @test err isa OptParse.IntegerValError
end

@testset "should handle empty state array with min constraint" begin
    baseParser = option(("-l", "--locale"), str())
    repeatedParser = many1(baseParser)

    comp = splitcomplete(repeatedParser, OptParse.ParseResult{String, Union{OptParse.ArgOptionError, OptParse.StringValError}}[])
    @test is_error(comp)
    err = unwrap_error(comp)
    @test err isa OptParse.ModMultipleError
    @test err.code == OptParse.MULTIPLE_TooFew
end

@testset "should handle max constraint at completion" begin
    baseParser = option(("-l", "--locale"), str())
    repeatedParser = repeated(baseParser; max = 2)

    mockStates = OptParse.ParseResult{String, Union{OptParse.ArgOptionError, OptParse.StringValError}}[Ok("en"), Ok("fr"), Ok("de")]
    comp = splitcomplete(repeatedParser, mockStates)
    @test is_error(comp)
    err = unwrap_error(comp)
    @test err isa OptParse.ModMultipleError
    @test err.code == OptParse.MULTIPLE_TooMany
end

@testset "should work with constant parsers" begin
    baseParser = @constant(:fixed)
    repeatedParser = repeated(baseParser; min = 1, max = 3)

    # Since constant parser does not consume input, implementation should avoid infinite loops
    val = parse_ok(repeatedParser, String[])
    @test val == [Val(:fixed)]
end

@testset "should reproduce example usage patterns" begin
    # Example 1
    parser1 = record(
        (
            name = option("-n", "--name", str()),
            locales = many(option(("-l", "--locale"), str())),
            id = arg(str()),
        )
    )
    val1 = parse_ok(parser1, ["-n", "John", "-l", "en-US", "-l", "fr-FR", "user123"])
    @test val1.name == "John"
    @test val1.locales == ["en-US", "fr-FR"]
    @test val1.id == "user123"

    # Example 2: constrained repeated arguments
    parser2 = record(
        (
            title = option("-t", "--title", str()),
            ids = repeated(arg(str()); min = 1, max = 3),
        )
    )
    val2 = parse_ok(parser2, ["-t", "My Title", "id1", "id2"])
    @test val2.title == "My Title"
    @test val2.ids == ["id1", "id2"]

    # Constraint violation: once `max` is reached, the extra positional is left
    # to the parent parser and surfaces as no further progress at top level.
    err = parse_fail(parser2, ["-t", "Title", "id1", "id2", "id3", "id4"])
    @test err isa OptParse.ConstrObjectError
    @test err.code == OptParse.OBJECT_UnexpectedToken
end

@testset "should handle options terminator correctly" begin
    parser = record(
        (
            locales = many(option(("-l", "--locale"), str())),
            args = many(arg(str())),
        )
    )

    val = parse_ok(parser, ["-l", "en", "--", "-l", "fr"])
    @test val.locales == ["en"]
    @test val.args == ["-l", "fr"]
end

@testset "should handle state transitions and updates correctly" begin
    baseParser = arg(str())
    repeatedParser = many(baseParser)

    # Test initial state
    @test repeatedParser.initialState == tval(baseParser)[]

    ctx1 = mkctx(["arg1"], repeatedParser.initialState)
    parseRes1 = splitparse(repeatedParser, ctx1)
    @test !is_error(parseRes1)
    succ1 = unwrap(parseRes1)
    @test length(res_nextstate(succ1)) == 1
    @test as_tuple(res_consumed(succ1)) == ("arg1",)

    # Next context with carried state but new buffer
    carried = res_nextstate(succ1)
    ctx2 = widen_state(tstate(repeatedParser), mkctx(["arg2"], carried))
    parseRes2 = @unionsplit  parse(repeatedParser, ctx2)
    @test !is_error(parseRes2)
    succ2 = unwrap(parseRes2)
    @test length(res_nextstate(succ2)) == 2
    @test as_tuple(res_consumed(succ2)) == ("arg2",)
end

@testset "should work with complex value parsers" begin
    baseParser = option(("-p", "--port"), integer(; min = 1024, max = 0xffff))
    repeatedParser = repeated(baseParser; min = 1, max = 5)

    validVals = parse_ok(repeatedParser, ["-p", "8080", "-p", "9000", "-p", "3000"])
    @test validVals == [8080, 9000, 3000]

    invalidErr = parse_fail(repeatedParser, ["-p", "8080", "-p", "100"])
    @test invalidErr isa OptParse.IntegerValError  # Should fail due to port 100 being below minimum

    tooManyErr = parse_fail(repeatedParser, ["-p", "8080", "-p", "9000", "-p", "3000", "-p", "4000", "-p", "5000", "-p", "6000"])
    @test tooManyErr isa OptParse.MainError
    @test tooManyErr.code == OptParse.MAIN_UnexpectedToken
end

@testset "should maintain type safety with different value types" begin
    stringRepeated = many(option("-s", str()))
    integerRepeated = many(option("-i", integer()))
    booleanRepeated = many(switch("-b"))

    # Strings
    sVals = parse_ok(stringRepeated, ["-s", "hello", "-s", "world"])
    @test length(sVals) == 2
    @test sVals[1] isa String
    @test sVals == ["hello", "world"]

    # Integers
    iVals = parse_ok(integerRepeated, ["-i", "42", "-i", "100"])
    @test length(iVals) == 2
    @test iVals[1] isa Int
    @test iVals == [42, 100]

    # Booleans
    bVals = parse_ok(booleanRepeated, ["-bb"])
    @test length(bVals) == 2
    @test bVals[1] isa Bool
    @test bVals == [true, true]
end
