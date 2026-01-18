@testset "should create a parser with same priority as wrapped parser" begin
    baseParser = option(("-l", "--locale"), str())
    multipleParser = multiple(baseParser)

    @test priority(multipleParser) == priority(baseParser)
    @test getproperty(multipleParser, :initialState) == tval(baseParser)[]
end

@testset "should parse multiple occurrences of wrapped parser" begin
    baseParser = option(("-l", "--locale"), str())
    multipleParser = multiple(baseParser)

    res = argparse(multipleParser, ["-l", "en", "-l", "fr", "-l", "de"])
    @test !is_error(res)

    val = unwrap(res)
    @test val == ["en", "fr", "de"]
end

@testset "should return empty array when no matches found in object context" begin
    parser = object(
        (
            locales = multiple(option(("-l", "--locale"), str())),
            verbose = flag("-v", "--verbose"),
        )
    )

    res = argparse(parser, ["-v"])
    @test !is_error(res)

    val = unwrap(res)
    @test getproperty(val, :locales) == []
    @test getproperty(val, :verbose) == true
end

@testset "should work with argument parsers" begin
    baseParser = argument(str())
    multipleParser = multiple(baseParser)

    res = argparse(multipleParser, ["file1.txt", "file2.txt", "file3.txt"])
    @test !is_error(res)

    val = unwrap(res)
    @test val == ["file1.txt", "file2.txt", "file3.txt"]
end

@testset "should enforce minimum constraint" begin
    baseParser = option(("-l", "--locale"), str())
    multipleParser = multiple(baseParser; min = 2)

    resTooFew = argparse(multipleParser, ["-l", "en"])
    @test is_error(resTooFew)
    err1 = unwrap_error(resTooFew)
    @test occursin("Expected at least 2 values, but got only 1", string(err1))

    resEnough = argparse(multipleParser, ["-l", "en", "-l", "fr"])
    @test !is_error(resEnough)
    val = unwrap(resEnough)
    @test val == ["en", "fr"]
end

@testset "should enforce maximum constraint" begin
    baseParser = argument(str())
    multipleParser = multiple(baseParser; max = 2)

    resTooMany = argparse(multipleParser, ["file1.txt", "file2.txt", "file3.txt"])
    @test is_error(resTooMany)
    err = unwrap_error(resTooMany)
    @test occursin("Expected at most 2 values, but got 3", err)

    resOkay = argparse(multipleParser, ["file1.txt", "file2.txt"])
    @test !is_error(resOkay)
    val = unwrap(resOkay)
    @test val == ["file1.txt", "file2.txt"]
end

@testset "should enforce both min and max constraints" begin
    baseParser = argument(str())
    multipleParser = multiple(baseParser; min = 1, max = 3)

    # When used standalone, multiple() fails if it can't parse at least one occurrence
    resTooFew = argparse(multipleParser, String[])
    @test is_error(resTooFew)
    @test occursin("Expected an argument, but got end of input", unwrap_error(resTooFew))

    resTooMany = argparse(multipleParser, ["a", "b", "c", "d"])
    @test is_error(resTooMany)
    @test occursin("Expected at most 3 values, but got 4", unwrap_error(resTooMany))

    resJustRight = argparse(multipleParser, ["a", "b"])
    @test !is_error(resJustRight)
    val = unwrap(resJustRight)
    @test val == ["a", "b"]
end

@testset "should work with default options (min=0, max=Infinity)" begin
    parser = object(
        (
            options = multiple(option("-x", str())),
            help = flag("-h", "--help"),
        )
    )

    # When min=0, should allow empty array in object context
    resEmpty = argparse(parser, ["-h"])
    @test !is_error(resEmpty)
    valEmpty = unwrap(resEmpty)
    @test getproperty(valEmpty, :options) == []
    @test getproperty(valEmpty, :help) == true

    # Test with many values to ensure no arbitrary limit
    manyArgs = String[]
    for i in 0:9
        append!(manyArgs, ["-x", "value$(i)"])
    end
    push!(manyArgs, "-h")

    resMany = argparse(parser, manyArgs)
    @test !is_error(resMany)
    valMany = unwrap(resMany)
    @test length(getproperty(valMany, :options)) == 10
    @test getproperty(valMany, :options)[1] == "value0"
    @test getproperty(valMany, :options)[10] == "value9"
    @test getproperty(valMany, :help) == true
end

@testset "should work in object combinations" begin
    parser = object(
        (
            locales = multiple(option(("-l", "--locale"), str())),
            verbose = flag("-v", "--verbose"),
            files = multiple(argument(str()); min = 1),
        )
    )

    res = argparse(parser, ["-l", "en", "-l", "fr", "-v", "file1.txt", "file2.txt"])
    @test !is_error(res)

    val = unwrap(res)
    @test getproperty(val, :locales) == ["en", "fr"]
    @test getproperty(val, :verbose) == true
    @test getproperty(val, :files) == ["file1.txt", "file2.txt"]
end

@testset "should propagate wrapped parser failures" begin
    baseParser = option(("-p", "--port"), integer(; min = 1, max = 0xffff))
    multipleParser = multiple(baseParser)

    res = argparse(multipleParser, ["-p", "8080", "-p", "invalid"])
    @test is_error(res)  # The failure should come from the invalid integer parsing
    @test occursin("Expected valid integer", string(unwrap_error(res)))
end

@testset "should handle mixed successful and failed parsing attempts in object context" begin
    parser = object(
        (
            numbers = multiple(option("-n", "--number", integer())),
            other = option("--other", str()),
        )
    )

    res = argparse(parser, ["-n", "42", "-n", "100", "--other", "value"])
    @test !is_error(res)

    val = unwrap(res)
    @test getproperty(val, :numbers) == [42, 100]
    @test getproperty(val, :other) == "value"
end

@testset "should work with boolean flag options" begin
    baseParser = flag("-v", "--verbose")
    multipleParser = multiple(baseParser)

    res = argparse(multipleParser, ["-v", "-v", "-v"])
    @test !is_error(res)

    val = unwrap(res)
    @test val == [true, true, true]
end

@testset "should handle parse context state management correctly" begin
    baseParser = option(("-l", "--locale"), str())
    multipleParser = multiple(baseParser)

    state = getproperty(multipleParser, :initialState)
    ctx1 = Context(buffer=["-l", "en", "-l", "fr"], state=state)

    parseRes1 = @unionsplit  parse(multipleParser, ctx1)
    @test !is_error(parseRes1)
    succ1 = unwrap(parseRes1)

    @test getproperty(succ1, :consumed) == ("-l", "en")
    @test length(getproperty(getproperty(succ1, :next), :state)) == 1

    # Parse next occurrence with updated buffer and carried state
    nextState1 = getproperty(getproperty(succ1, :next), :state)
    ctx2 = Context(buffer=["-l", "fr"], state=nextState1)

    parseRes2 = @unionsplit  parse(multipleParser, ctx2)
    @test !is_error(parseRes2)
    succ2 = unwrap(parseRes2)

    @test getproperty(succ2, :consumed) == ("-l", "fr")
    @test length(getproperty(getproperty(succ2, :next), :state)) == 2
end

@testset "should complete with proper value array" begin
    baseParser = option("-n", "--number", integer())
    multipleParser = multiple(baseParser)


    mockStates = Result{Int, String}[Ok(42), Ok(100), Ok(7)]
    comp = @unionsplit complete(multipleParser, mockStates)
    @test !is_error(comp)
    @test unwrap(comp) == [42, 100, 7]
end

@testset "should fail completion if wrapped parser completion fails" begin
    baseParser = option("-n", "--number", integer())
    multipleParser = multiple(baseParser)

    mockStates = Result{Int, String}[Ok(42), Err("Invalid number"), Ok(7)]
    comp = @unionsplit complete(multipleParser, mockStates)
    @test is_error(comp)
    @test occursin("Invalid number", string(unwrap_error(comp)))
end

@testset "should handle empty state array with min constraint" begin
    baseParser = option(("-l", "--locale"), str())
    multipleParser = multiple(baseParser; min = 1)

    comp = @unionsplit complete(multipleParser, Result{String, String}[])
    @test is_error(comp)
    @test occursin("Expected at least 1 values, but got only 0", string(unwrap_error(comp)))
end

@testset "should handle max constraint at completion" begin
    baseParser = option(("-l", "--locale"), str())
    multipleParser = multiple(baseParser; max = 2)

    mockStates = Result{String, String}[Ok("en"), Ok("fr"), Ok("de")]
    comp = @unionsplit complete(multipleParser, mockStates)
    @test is_error(comp)
    @test occursin("Expected at most 2 values, but got 3", string(unwrap_error(comp)))
end

@testset "should work with constant parsers" begin
    baseParser = @constant(:fixed)
    multipleParser = multiple(baseParser; min = 1, max = 3)

    # Since constant parser does not consume input, implementation should avoid infinite loops
    res = argparse(multipleParser, String[])
    @test !is_error(res)

    val = unwrap(res)
    @test val == [Val(:fixed)]
end

@testset "should reproduce example usage patterns" begin
    # Example 1
    parser1 = object(
        (
            name = option("-n", "--name", str()),
            locales = multiple(option(("-l", "--locale"), str())),
            id = argument(str()),
        )
    )
    res1 = argparse(parser1, ["-n", "John", "-l", "en-US", "-l", "fr-FR", "user123"])
    @test !is_error(res1)
    val1 = unwrap(res1)
    @test getproperty(val1, :name) == "John"
    @test getproperty(val1, :locales) == ["en-US", "fr-FR"]
    @test getproperty(val1, :id) == "user123"

    # Example 2: constrained multiple arguments
    parser2 = object(
        (
            title = option("-t", "--title", str()),
            ids = multiple(argument(str()); min = 1, max = 3),
        )
    )
    res2 = argparse(parser2, ["-t", "My Title", "id1", "id2"])
    @test !is_error(res2)
    val2 = unwrap(res2)
    @test getproperty(val2, :title) == "My Title"
    @test getproperty(val2, :ids) == ["id1", "id2"]

    # Constraint violation
    res3 = argparse(parser2, ["-t", "Title", "id1", "id2", "id3", "id4"])
    @test is_error(res3)
    @test occursin("Expected at most 3 values, but got 4", string(unwrap_error(res3)))
end

@testset "should handle options terminator correctly" begin
    parser = object(
        (
            locales = multiple(option(("-l", "--locale"), str())),
            args = multiple(argument(str())),
        )
    )

    res = argparse(parser, ["-l", "en", "--", "-l", "fr"])
    @test !is_error(res)

    val = unwrap(res)
    @test getproperty(val, :locales) == ["en"]
    @test getproperty(val, :args) == ["-l", "fr"]
end

@testset "should handle state transitions and updates correctly" begin
    baseParser = argument(str())
    multipleParser = multiple(baseParser)

    # Test initial state
    @test getproperty(multipleParser, :initialState) == tval(baseParser)[]

    ctx1 = Context{tstate(multipleParser)}(["arg1"], getproperty(multipleParser, :initialState), false)
    parseRes1 = @unionsplit  parse(multipleParser, ctx1)
    @test !is_error(parseRes1)
    succ1 = unwrap(parseRes1)
    @test length(getproperty(getproperty(succ1, :next), :state)) == 1
    @test getproperty(succ1, :consumed) == ("arg1",)

    # Next context with carried state but new buffer
    carried = getproperty(getproperty(succ1, :next), :state)
    ctx2 = Context{tstate(multipleParser)}(["arg2"], carried, false)
    parseRes2 = @unionsplit  parse(multipleParser, ctx2)
    @test !is_error(parseRes2)
    succ2 = unwrap(parseRes2)
    @test length(getproperty(getproperty(succ2, :next), :state)) == 2
    @test getproperty(succ2, :consumed) == ("arg2",)
end

@testset "should work with complex value parsers" begin
    baseParser = option(("-p", "--port"), integer(; min = 1024, max = 0xffff))
    multipleParser = multiple(baseParser; min = 1, max = 5)

    validRes = argparse(multipleParser, ["-p", "8080", "-p", "9000", "-p", "3000"])
    @test !is_error(validRes)
    validVals = unwrap(validRes)
    @test validVals == [8080, 9000, 3000]

    invalidRes = argparse(multipleParser, ["-p", "8080", "-p", "100"])
    @test is_error(invalidRes)  # Should fail due to port 100 being below minimum

    tooManyRes = argparse(multipleParser, ["-p", "8080", "-p", "9000", "-p", "3000", "-p", "4000", "-p", "5000", "-p", "6000"])
    @test is_error(tooManyRes)
    @test occursin("Expected at most 5 values, but got 6", string(unwrap_error(tooManyRes)))
end

@testset "should maintain type safety with different value types" begin
    stringMultiple = multiple(option("-s", str()))
    integerMultiple = multiple(option("-i", integer()))
    booleanMultiple = multiple(flag("-b"))

    # Strings
    stringRes = argparse(stringMultiple, ["-s", "hello", "-s", "world"])
    @test !is_error(stringRes)
    sVals = unwrap(stringRes)
    @test length(sVals) == 2
    @test sVals[1] isa String
    @test sVals == ["hello", "world"]

    # Integers
    integerRes = argparse(integerMultiple, ["-i", "42", "-i", "100"])
    @test !is_error(integerRes)
    iVals = unwrap(integerRes)
    @test length(iVals) == 2
    @test iVals[1] isa Int
    @test iVals == [42, 100]

    # Booleans
    booleanRes = argparse(booleanMultiple, ["-bb"])
    @test !is_error(booleanRes)
    bVals = unwrap(booleanRes)
    @test length(bVals) == 2
    @test bVals[1] isa Bool
    @test bVals == [true, true]
end
