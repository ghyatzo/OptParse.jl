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

        # @test "should fail when passed strings" begin
        #     @test_throws "Symbol" @constant("hello")
        # end

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
            parser = flag("-v")
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
            parser = flag("--verbose")
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
            parser = flag("-v", "--verbose")

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
            parser = flag("-v")
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
            parser = flag("-v")
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
            parser = flag("-v")
            context = Context(["-v"], parser.initialState, true)

            result = @unionsplit parse(parser, context)

            @test is_error(result)
            unwrap_or_else(result) do fail
                @test fail.consumed == 0
                @test occursin("No more", fail.error)
            end
        end

        @testset "should handle flags terminator --" begin
            parser = flag("-v")
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
            parser = flag("-v")
            context = Context(String[], parser.initialState, false)

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

            context = Context(["-v"], parser.initialState, false)

            _p(par, ctx) = @unionsplit parse(par, ctx)
            @test_opt _p(parser, context)
        end
    end

    @testset "Option parser" begin
        @testset "should parse option with separated value" begin
            parser = option(("-p", "--port"), integer())
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
            parser = option("--port", integer())
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
            parser = option("--port", integer())
            context = Context(["--port"], parser.initialState)

            res = @unionsplit parse(parser, context)

            @test is_error(res)  # failure
            pf = unwrap_error(res)  # :: ParseFailure

            @test pf.consumed == 1
            @test occursin("requires a value", string(pf.error))
        end

        @testset "should parse string values" begin
            parser = option("--name", str(; metavar = "NAME"))
            context = Context(["--name", "Alice"], parser.initialState)

            res = @unionsplit parse(parser, context)

            @test !is_error(res)
            ps = unwrap(res)

            @test !is_error(ps.next.state)
            @test unwrap(ps.next.state) == "Alice"
        end

        @testset "should propagate value parser failures" begin
            parser = option("--port", integer(; min = 1, max = 0xffff))
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
            parser = option(("-v", "--verbose"), choice(["yes", "no"]))
            context = Context(["--help"], parser.initialState)

            res = @unionsplit parse(parser, context)

            @test is_error(res)
            pf = unwrap_error(res)

            @test pf.consumed == 0
            @test occursin("No Matched", string(pf.error))
        end

        @testset "should be type stable" begin
            @test_opt option("--port", integer())
            parser = option("--port", integer())

            context = Context(["--port", "8080"], parser.initialState, false)

            _p(par, ctx) = @unionsplit parse(par, ctx)
            @test_opt _p(parser, context)
        end
    end
end

@testset "Constructors" begin
    @testset "Objects" begin

    @testset "should combine multiple parsers into an object" begin
        parser = object((
            verbose = flag("-v", "--verbose"),
            port    = option(("-p", "--port"), integer()),
        ))

        @test priority(parser) >= 10

        # initialState should contain fields :verbose and :port
        @test hasproperty(parser, :initialState)
        names = propertynames(parser.initialState)
        @test :verbose in names
        @test :port in names
    end

    @testset "should parse multiple options in sequence" begin
        parser = object((
            verbose = flag("-v"),
            port    = option("-p", integer()),
        ))

        argv = ["-v", "-p", "8080"]
        ctx = Context(argv, parser.initialState)
        res = parse(parser, ctx)

        @test !is_error(res)
        if !is_error(res)
            ps = unwrap(res)
            st = ps.next.state
            @test haskey(Dict(propertynames(st) .=> getfield.(Ref(st), propertynames(st))), :verbose)
            @test haskey(Dict(propertynames(st) .=> getfield.(Ref(st), propertynames(st))), :port)
            @test (@? getfield(st, :verbose)) == true
            @test (@? getfield(st, :port)) == 8080
        end
    end

    @testset "should work with labeled objects" begin
        parser = object("Test Group", (
            flag = flag("-f"),
        ))

        @test hasproperty(parser, :initialState)
        names = propertynames(parser.initialState)
        @test :flag in names
    end

    @testset "should handle parsing failure in nested parser" begin
        parser = object((
            port = option("-p", integer(; min=1)),
        ))

        argv = ["-p", "0"]
        ctx = Context(argv, parser.initialState)
        res = parse(parser, ctx)

        @test is_error(res)
    end

    @testset "should fail when no option matches" begin
        parser = object((
            verbose = flag("-v"),
        ))

        buffer = ["--help"]
        state = parser.initialState
        ctx = Context(buffer, state)  # optionsTerminated defaults to false
        res = parse(parser, ctx)

        @test is_error(res)
        if is_error(res)
            pf = unwrap_error(res)
            @test pf.consumed == 0
            @test occursin("Unexpected option", string(pf.error))
        end
    end

    @testset "should handle empty arguments gracefully when required options are present" begin
        parser = object((
            verbose = flag("-v"),
            port    = option( "-p", integer()),
        ))

        argv = String[]
        ctx = Context(argv, parser.initialState)
        res = parse(parser, ctx)

        @test is_error(res)
        if is_error(res)
            pf = unwrap_error(res)
            @test occursin("Expected an option", string(pf.error))
        end
    end

    # @testset "should succeed with empty input when only Boolean flags are present" begin
    #     parser = object((
    #         watch = flag("--watch"),
    #     ))

    #     argv = String[]
    #     ctx = Context(argv, parser.initialState)
    #     res = parse(parser, ctx)

    #     @test !is_error(res)
    #     if !is_error(res)
    #         st = unwrap(res).next.state
    #         @test getfield(st, :watch) == false
    #     end
    # end

    # @testset "should succeed with empty input when multiple Boolean flags are present" begin
    #     parser = object((
    #         watch   = flag("--watch"),
    #         verbose = flag("--verbose"),
    #         debug   = flag("--debug"),
    #     ))

    #     argv = String[]
    #     ctx = Context(argv, parser.initialState)
    #     res = parse(parser, ctx)

    #     @test !is_error(res)
    #     if !is_error(res)
    #         st = unwrap(res).next.state
    #         @test getfield(st, :watch) == false
    #         @test getfield(st, :verbose) == false
    #         @test getfield(st, :debug) == false
    #     end
    # end

    # @Testset "should parse Boolean flags correctly when provided" begin
    #     parser = object((
    #         watch   = flag("--watch"),
    #         verbose = flag("--verbose"),
    #     ))

    #     argv = ["--watch"]
    #     ctx = Context(argv, parser.initialState)
    #     res = parse(parser, ctx)

    #     @test !is_error(res)
    #     if !is_error(res)
    #         st = unwrap(res).next.state
    #         @test getfield(st, :watch) == true
    #         @test getfield(st, :verbose) == false
    #     end
    # end

    end
end

@testset "Modifiers" begin
   @testset "Optional parser" begin

        @testset "should create a parser with same priority as wrapped parser" begin
            baseParser     = flag("-v", "--verbose")
            optionalParser = optional(baseParser)

            @test priority(optionalParser) == priority(baseParser)
            # @test optionalParser.initialState === nothing
            @test optionalParser.initialState === none(tstate(baseParser))
        end

        @testset "should return wrapped parser value when it succeeds" begin
            baseParser     = flag("-v", "--verbose")
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
            baseParser     = option(("-n", "--name"), str())
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
            baseParser     = flag("-v", "--verbose")
            optionalParser = optional(baseParser)

            context = Context(["--help"], optionalParser.initialState)
            parseResult = parse(optionalParser, context)

            @test is_error(parseResult)
            # pf = unwrap_error(parseResult)

            # @test pf.consumed == 0
            # @test occursin("No matched option", string(pf.error))
        end

        @testset "should complete with undefined when internal state is undefined" begin
            baseParser     = flag("-v", "--verbose")
            optionalParser = optional(baseParser)

            completeResult = complete(optionalParser, none(tstate(baseParser)))

            @test !is_error(completeResult)
            @test unwrap(completeResult) === none(Bool)
        end

        @testset "should complete with wrapped parser result when state is defined" begin
            baseParser     = flag("-v", "--verbose")
            optionalParser = optional(baseParser)

            # Simulate a collected successful inner state (as optional.parse would)
            successfulState = some(Result{Bool, String}(Ok(true)))
            completeResult  = complete(optionalParser, successfulState)

            @test !is_error(completeResult)
            @test unwrap(completeResult) == some(true)
        end

        @testset "should propagate wrapped parser completion failures" begin
            baseParser     = option(("-p", "--port"), integer(; min = 1))
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
            baseParser     = flag("-v", "--verbose")
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
            baseParser     = flag("-v")
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
            baseParser     = option(("-n", "--name"), str())
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

        @testset "should be type stable" begin
            baseParser     = option(("-n", "--name"), str())
            @test_opt optional(baseParser)
            optionalParser = optional(baseParser)

            # initial state should be "undefined" (nothing)
            @test optionalParser.initialState === none(tstate(baseParser))

            context     = Context(["-n", "test"], none(tstate(optionalParser)))

            @test_opt parse(optionalParser, context)
        end
    end
end


#=

You are translating a suite of unit tests from TypeScript to Julia.

Context / Domain Types (use exactly these; include them in your mental model but do NOT re-define them unless I ask)
using ErrorTypes

struct Context{S}
    buffer::Vector{String}
    state::S                 # accumulator for partial states (e.g. NamedTuple or parser-specific state)
    optionsTerminated::Bool
end
Context(args::Vector{String}, state) = Context{typeof(state)}(args, state, false)

struct ParseSuccess{S}
    consumed::Tuple{Vararg{String}}
    next::Context{S}
end
ParseSuccess(cons::Vector{String}, next) = ParseSuccess((cons...), next)
ParseSuccess(cons::String,         next) = ParseSuccess((cons,),  next)

struct ParseFailure{E}
    consumed::Int
    error::E
end

const ParseResult{S,E} = Result{ParseSuccess{S}, ParseFailure{E}}

Required API shape (important)
- Do not use method-style calls (no `parser.parse`, no `parser.complete`).
- Always use the free functions exactly as:
  - parse(parser, context::Context)
  - complete(parser, state)
- When a TS test calls parse with an argv array, construct a Context first:
  - ctx = Context(argv_vector, parser.initialState)
  - res = parse(parser, ctx)
- For tests that require optionsTerminated = true, construct explicitly:
  - Context{typeof(state)}(buffer, state, true)

ErrorTypes.jl usage
- Treat all parser results as Result/Option from ErrorTypes.jl.
- Use:
  - is_error(x) to test failure
  - unwrap(x) to access success payload
  - unwrap_error(x) (v0.5+ spelling) to access failure payload
- For TS’s assertErrorIncludes(result.error, "..."), write:
  - @test occursin("...", string(error_or_result))
- Use `nothing` where TS expects `undefined`.

Structural differences to respect
- ParseSuccess.consumed is a tuple of String in Julia.
  Compare with tuple literals, e.g. ("-v",) or ("--port","8080").
  Do not compare to Vector unless you intentionally convert.
- Context.buffer is Vector{String}; compare to String[] for empty.
- Do not mutate structs; construct new Context values when "updating".
- option parser takes the value parser as first argument: like so option(integer(), "--option", "-o")

Style constraints for the translation
- Do not introduce any helper functions or macros in tests (no test helpers).
- Do not mimic TS assertion style; just preserve the logic of what is being checked.
- Use plain @test, is_error(...), unwrap(...), unwrap_error(...), direct field access, and occursin(...).
- Keep one @testset per TS it(...) block with the same description.
- When TS checks Array.isArray(state), assert the logically equivalent Julia property (e.g., state isa AbstractVector) and length checks as needed.
- When TS expects undefined, assert `=== nothing`.
- If a TS test manually feeds a completion state, mirror that with Vector{Result} values, e.g. [Ok(true)] or [Err("message")], unless the parser exposes an exact type; only assert what TS asserts (value or message).

Output format
- Produce one Julia test file content (a single code block), ready to save under test/..._tests.jl.
- At the top of the file, include: using Test, using ErrorTypes, and any needed module imports (assume a placeholder YourParserModule if necessary, but keep it commented).
- Translate exactly the TS it(...) cases I provide, in order, into @testset blocks with the same names.
- Ensure every test uses the free-function API: parse(parser, context) and complete(parser, state).

The tests to translate (TypeScript) — translate ALL of them below
Paste them verbatim between the markers. Do not summarize; output only the Julia test file content.

---BEGIN-TS-TESTS---
(paste the TypeScript `it(...)` test blocks here)


=#