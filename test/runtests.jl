using Test
using ComposableCLIParse
using ComposableCLIParse: Context, parse, priority, complete, tstate, tval
using ErrorTypes
using WrappedUnions: @unionsplit
using JET
using UUIDs

@testset "Value Parsers" begin

    @testset "StringVal" begin
        sval = str(metavar = "TEST", pattern = r"^A.*")
        @test (@? sval("AAA")) == "AAA"
        @test is_error(sval("BBB"))
        @test_opt sval("AAA")
    end

    @testset "Choice" begin
        ch = choice(["HELLO", "WoRlD"], metavar = "TEST", caseInsensitive = true)
        @test (@? ch("HELLO")) == "hello"
        @test (@? ch("world")) == "world"
        @test is_error(ch("!!!"))

        @test_opt ch("world")
    end

    @testset "IntegerVal" begin
        iv = integer(Int32, min = 10, max = 20)
        @test (@? iv("13")) == Int32(13)
        err = iv("3")
        @test is_error(err) && occursin("minimum", unwrap_error(err))
        err = iv("222")
        @test is_error(err) && occursin("maximum", unwrap_error(err))

        @test_opt iv("15")
    end

    @testset "FloatVal" begin
        f = flt(Float32, min = 0.2, max = 120.3)
        @test (@? f("3.14")) == Float32(3.14)

        err = f("200")
        @test is_error(err) && occursin("maximum", unwrap_error(err))
        err = f("0")
        @test is_error(err) && occursin("minimum", unwrap_error(err))
        err = f("inf")
        @test is_error(err) && occursin("Infinite", unwrap_error(err))
        err = f("nan")
        @test is_error(err) && occursin("NaNs", unwrap_error(err))

        finfnan = flt(allowInfinity=true, allowNan = true)
        @test isinf(@? finfnan("-inf"))
        @test isnan(@? finfnan("nan"))

        @test_opt f("1.2")
    end

    @testset "UUIDVal" begin
        u = uuid(allowedVersions = [1, 4])
        u1 = string(uuid1())
        u4 = string(uuid4())
        u7 = string(uuid7())

        @test (@? u(u1)) == UUID(u1)
        @test uuid_version(@? u(u1)) == 1

        @test (@? u(u4)) == UUID(u4)
        @test uuid_version(@? u(u4)) == 4

        err = u(u7)
        @test is_error(err) && occursin("version", unwrap_error(err))

        @test_opt u(u1)
    end

end

@testset "Primitives" begin

    using ComposableCLIParse: Context, parse, priority, complete

    @testset "Constant parser" begin
        @testset "should create a parser that always returns the same value" begin
            parser = @constant(42)

            @test priority(parser) == 0
            @test unwrap(parser.initialState) == Val(42)
        end

        @testset "should parse without consuming any input" begin
            parser = @constant(:hello)
            context = Context(["--option", "value"], Result{Val{:hello}, String}(Ok(Val(:hello))))

            result = @unionsplit parse(parser, context)
            @test is_ok_and(result) do succ
                @test succ.consumed == ()
                @test succ.next == context
                !is_error(result)
            end
        end

        @test "should fail when passed strings" begin
            @test_throws parser = @constant("hello")
        end
        
        @testset "should complete successfully with a constant value" begin
            parser = @constant(69)
            result = complete(parser, Result{Val{69}, String}(Ok(Val(69))))

            @test is_ok_and(result) do succ
                @test succ == 69
                !is_error(result)
            end
        end
        @testset "should work with different value types" begin
            stringconst = @constant(:hello)
            intconst = @constant(123)
            boolconst = @constant(true)
            namedtupleconst = @constant((key = :value,))

            @test (@? complete(stringconst,     Result{Val{:hello}, String}(Ok(Val(:hello))))) == :hello
            @test (@? complete(intconst,        Result{Val{123}, String}(Ok(Val(123))))) == 123
            @test (@? complete(boolconst,       Result{Val{true}, String}(Ok(Val(true))))) == true
            @test (@? complete(namedtupleconst, Result{Val{(key = :value,)}, String}(Ok(Val((key = :value,)))))) == (key = :value,)
        end

        @testset "should be type stable" begin
            @test_opt @constant(:hello)
            @test_opt @constant(123)
            @test_opt @constant(true)
            @test_opt @constant((key = :value,))
        end
    end


    @testset "Flag parser" begin

        @testset "should parse single short flag" begin
            parser = flag(["-v"])
            context = Context(["-v"], parser.initialState, false)

            result = @unionsplit parse(parser, context)

            @test is_ok_and(result) do succ
                is_ok_and(==(true), succ.next.state)
            end
            succ = unwrap(result)
            @test succ.next.buffer == String[]
            @test succ.consumed == ("-v",)
        end

        @testset "should parse long flag" begin
            parser = flag(["--verbose"])
            context = Context(["--verbose"], parser.initialState, false)

            result = @unionsplit parse(parser, context)

            @test is_ok_and(result) do succ
                is_ok_and(==(true), succ.next.state)
            end
            succ = unwrap(result)
            @test succ.next.buffer == String[]
            @test succ.consumed == ("--verbose",)
        end

        @testset "should parse multiple flag names" begin
            parser = flag(["-v", "--verbose"])

            # First: "-v"
            context1 = Context(["-v"], parser.initialState, false)
            result1 = @unionsplit parse(parser, context1)
            @test is_ok_and(result1) do succ
                is_ok_and(==(true), succ.next.state)
            end

            # Second: "--verbose"
            context2 = Context(["--verbose"], parser.initialState, false)
            result2 = @unionsplit parse(parser, context2)
            @test is_ok_and(result2) do succ
                is_ok_and(==(true), succ.next.state)
            end
        end

        @testset "should fail when flag is already set" begin
            parser = flag(["-v"])
            # Represent "already set" using Result-based state:
            context = Context(["-v"], Result{Bool, String}(Ok(true)), false)

            result = @unionsplit parse(parser, context)

            @test is_error(result)
            unwrap_or_else(result) do fail
                @test fail.consumed == 1
                @test occursin("cannot be used multiple times", fail.error)
            end
        end

        @testset "should handle bundled short flags" begin
            parser = flag(["-v"])
            context = Context(["-vd"], parser.initialState, false)

            result = @unionsplit parse(parser, context)

            @test is_ok_and(result) do succ
                is_ok_and(==(true), succ.next.state)
            end
            succ = unwrap(result)
            @test succ.next.buffer == ["-d"]
            @test succ.consumed == ("-v",)
        end

        @testset "should fail when flags are terminated" begin
            parser = flag(["-v"])
            context = Context(["-v"], parser.initialState, true)

            result = @unionsplit parse(parser, context)

            @test is_error(result)
            unwrap_or_else(result) do fail
                @test fail.consumed == 0
                @test occursin("No more", fail.error)
            end
        end

        @testset "should handle flags terminator --" begin
            parser = flag(["-v"])
            context = Context(["--"], parser.initialState, false)

            result = @unionsplit parse(parser, context)

            @test !is_error(result)
            is_ok_and(result) do succ
                @test succ.next.optionsTerminated == true
                @test succ.next.buffer == String[]
                @test succ.consumed == ("--",)
                true
            end
        end

        @testset "should handle empty buffer" begin
            parser = flag(["-v"])
            context = Context(String[], parser.initialState, false)

            result = @unionsplit parse(parser, context)

            @test is_error(result)
            unwrap_or_else(result) do fail
                @test fail.consumed == 0
                @test occursin("Expected a", fail.error)
            end
        end

        @testset "should be type stable" begin
            @test_opt flag(["-v"])
            parser = flag(["-v"])

            context = Context(["-v"], parser.initialState, false)

            _p(par, ctx) = @unionsplit parse(par, ctx)
            @test_opt _p(parser, context)
        end
    end

    @testset "Option parser" begin
        @testset "should parse option with separated value" begin
            parser = option(["-p", "--port"], integer())
            context = Context(["--port", "8080"], parser.initialState)

            res = @unionsplit parse(parser, context)  # :: ParseResult

            @test !is_error(res)  # success
            ps = unwrap(res)      # :: ParseSuccess

            # next.state should itself be a successful value (Result/Option)
            @test !is_error(ps.next.state)
            @test unwrap(ps.next.state) == 8080

            @test ps.next.buffer == String[]  # buffer consumed
            @test ps.consumed == ("--port", "8080")  # tuple, not Vector
        end

        @testset "should parse option with equals-separated value" begin
            parser = option(["--port"], integer())
            context = Context(["--port=8080"], parser.initialState)

            res = @unionsplit parse(parser, context)

            @test !is_error(res)
            ps = unwrap(res)

            @test !is_error(ps.next.state)
            @test unwrap(ps.next.state) == 8080

            @test ps.next.buffer == String[]
            @test ps.consumed == ("--port=8080",)
        end

        # @testset "should parse DOS-style option with colon" begin
        #     parser  = option("/P", integer())
        #     context = Context(["/P:8080"], parser.initialState)

        #     res = @unionsplit parse(parser, context)

        #     @test !is_error(res)
        #     ps = unwrap(res)

        #     @test !is_error(ps.next.state)
        #     @test unwrap(ps.next.state) == 8080
        #     # TS test does not check buffer/consumed here
        # end

        @testset "should fail when value is missing" begin
            parser = option(["--port"], integer())
            context = Context(["--port"], parser.initialState)

            res = @unionsplit parse(parser, context)

            @test is_error(res)  # failure
            pf = unwrap_error(res)  # :: ParseFailure

            @test pf.consumed == 1
            @test occursin("requires a value", string(pf.error))
        end

        @testset "should parse string values" begin
            parser = option(["--name"], str(; metavar = "NAME"))
            context = Context(["--name", "Alice"], parser.initialState)

            res = @unionsplit parse(parser, context)

            @test !is_error(res)
            ps = unwrap(res)

            @test !is_error(ps.next.state)
            @test unwrap(ps.next.state) == "Alice"
        end

        @testset "should propagate value parser failures" begin
            parser = option(["--port"], integer(; min = 1, max = 0xffff))
            context = Context(["--port", "invalid"], parser.initialState)

            res = @unionsplit parse(parser, context)

            # Option itself matched, so overall parse succeeds...
            @test !is_error(res)
            ps = unwrap(res)

            # ...but the inner value parser failed (carry failure in state)
            @test is_error(ps.next.state)
            @test occursin("Expected valid integer", string(unwrap_error(ps.next.state)))
        end

        @testset "should fail on unmatched option" begin
            parser = option(["-v", "--verbose"], choice(["yes", "no"]))
            context = Context(["--help"], parser.initialState)

            res = @unionsplit parse(parser, context)

            @test is_error(res)
            pf = unwrap_error(res)

            @test pf.consumed == 0
            @test occursin("No Matched", string(pf.error))
        end

        @testset "should be type stable" begin
            @test_opt option(["--port"], integer())
            parser = option(["--port"], integer())

            context = Context(["--port", "8080"], parser.initialState, false)

            _p(par, ctx) = @unionsplit parse(par, ctx)
            @test_opt _p(parser, context)
        end
    end
end

@testset "Modifiers" begin
   @testset "Optional parser" begin

        @testset "should create a parser with same priority as wrapped parser" begin
            baseParser     = flag(["-v", "--verbose"])
            optionalParser = optional(baseParser)

            @test priority(optionalParser) == priority(baseParser)
            # @test optionalParser.initialState === nothing
            @test optionalParser.initialState === none(tstate(baseParser))
        end

        @testset "should return wrapped parser value when it succeeds" begin
            baseParser     = flag(["-v", "--verbose"])
            optionalParser = optional(baseParser)

            context = Context(["-v"], optionalParser.initialState)
            parseResult = parse(optionalParser, context)

            @test !is_error(parseResult)
            ps = unwrap(parseResult)

            # Completing the optional with the state produced by parse
            completeResult = complete(optionalParser, ps.next.state)
            @test !is_error(completeResult)
            @test unwrap(completeResult) == some(true)
        end

        @testset "should propagate successful parse results" begin
            baseParser     = option(["-n", "--name"], str())
            optionalParser = optional(baseParser)

            context = Context(["-n", "Alice"], optionalParser.initialState)
            parseResult = parse(optionalParser, context)

            @test !is_error(parseResult)
            ps = unwrap(parseResult)

            @test ps.next.buffer == String[]
            @test ps.consumed == ("-n", "Alice")

            # # optional keeps a collection of inner states
            # @test ps.next.state isa AbstractVector
            # @test length(ps.next.state) == 1
        end

        @testset "should propagate failed parse results" begin
            baseParser     = flag(["-v", "--verbose"])
            optionalParser = optional(baseParser)

            context = Context(["--help"], optionalParser.initialState)
            parseResult = parse(optionalParser, context)

            @test is_error(parseResult)
            # pf = unwrap_error(parseResult)

            # @test pf.consumed == 0
            # @test occursin("No matched option", string(pf.error))
        end

        @testset "should complete with undefined when internal state is undefined" begin
            baseParser     = flag(["-v", "--verbose"])
            optionalParser = optional(baseParser)

            completeResult = complete(optionalParser, none(tstate(baseParser)))

            @test !is_error(completeResult)
            @test unwrap(completeResult) === none(Bool)
        end

        @testset "should complete with wrapped parser result when state is defined" begin
            baseParser     = flag(["-v", "--verbose"])
            optionalParser = optional(baseParser)

            # Simulate a collected successful inner state (as optional.parse would)
            successfulState = some(Result{Bool, String}(Ok(true)))
            completeResult  = complete(optionalParser, successfulState)

            @test !is_error(completeResult)
            @test unwrap(completeResult) == some(true)
        end

        @testset "should propagate wrapped parser completion failures" begin
            baseParser     = option(["-p", "--port"], integer(; min = 1))
            optionalParser = optional(baseParser)

            # Simulate a collected failed inner state
            failedState    = some(Result{Int, String}(Err("Port must be >= 1")))
            completeResult = complete(optionalParser, failedState)

            @test is_error(completeResult)
            @test occursin("Port must be >= 1", string(unwrap_error(completeResult)))
        end

        # @testset "should work in object combinations - main use case" begin
        #     parser = object((
        #         verbose = option(["-v", "--verbose"]),
        #         port    = optional(option("-p", "--port", integer())),
        #         output  = optional(option("-o", "--output", string())),
        #     ))

        #     resultWithOptional = parse(parser, ["-v", "-p", "8080"])
        #     @test !is_error(resultWithOptional)
        #     val = unwrap(resultWithOptional)
        #     @test val.verbose == true
        #     @test val.port    == 8080
        #     @test val.output  === nothing  # TS undefined -> Julia nothing

        #     resultWithoutOptional = parse(parser, ["-v"])
        #     @test !is_error(resultWithoutOptional)
        #     val2 = unwrap(resultWithoutOptional)
        #     @test val2.verbose == true
        #     @test val2.port    === nothing
        #     @test val2.output  === nothing
        # end

        @testset "should work with constant parsers" begin
            baseParser     = @constant(:hello)
            optionalParser = optional(baseParser)

            context     = Context(String[], optionalParser.initialState)
            parseResult = parse(optionalParser, context)

            @test !is_error(parseResult)
            ps = unwrap(parseResult)

            completeResult = complete(optionalParser, ps.next.state)
            @test !is_error(completeResult)
            @test unwrap(completeResult) == some(:hello)
        end

        @testset "should handle options terminator" begin
            baseParser     = flag(["-v", "--verbose"])
            optionalParser = optional(baseParser)

            context = Context(["-v"], optionalParser.initialState)
            context = Context{typeof(context.state)}(context.buffer, context.state, true)  # optionsTerminated=true

            parseResult = parse(optionalParser, context)
            @test is_error(parseResult)
            pf = unwrap_error(parseResult)

            @test pf.consumed == 0
            @test occursin("No more options", string(pf.error))
        end

        @testset "should work with bundled short options through wrapped parser" begin
            baseParser     = flag(["-v"])
            optionalParser = optional(baseParser)

            context     = Context(["-vd"], optionalParser.initialState)
            parseResult = parse(optionalParser, context)

            @test !is_error(parseResult)
            ps = unwrap(parseResult)

            @test ps.next.buffer == ["-d"]
            @test ps.consumed    == ("-v",)

            completeResult = complete(optionalParser, ps.next.state)
            @test !is_error(completeResult)
            @test unwrap(completeResult) == some(true)
        end

        @testset "should handle state transitions" begin
            baseParser     = option(["-n", "--name"], str())
            optionalParser = optional(baseParser)

            # initial state should be "undefined" (nothing)
            @test optionalParser.initialState === none(tstate(baseParser))

            context     = Context(["-n", "test"], none(tstate(optionalParser)))
            parseResult = parse(optionalParser, context)

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
    end
end
