using Test
using CLIpper
using CLIpper: Context, parse, priority, complete, tstate, tval, Parser
using ErrorTypes
using WrappedUnions: @unionsplit, unwrap as unwrapunion
using JET
using UUIDs

# define it here for ease of use
splitparse(p::Parser, ctx::Context) = @unionsplit parse(p, ctx)
splitcomplete(p::Parser, st) = @unionsplit complete(p, st)

@testset "Value Parsers" begin

    include("valueparsers.jl")

end

@testset "Primitives" begin

    @testset "Constant parser" begin
        include("primitives/constant.jl")
    end

    @testset "Flag parser" begin
        include("primitives/flag.jl")
    end

    @testset "Option parser" begin
        include("primitives/option.jl")
    end

    @testset "Argument parser" begin
        include("primitives/argument.jl")
    end

    @testset "Command parser" begin
        include("primitives/command.jl")
    end
end

@testset "Constructors" begin

    @testset "Objects" begin
        include("constructors/object.jl")
    end

    @testset "Or" begin
        include("constructors/or.jl")
    end

    @testset "Tup" begin
        include("constructors/tup.jl")
    end

end

@testset "Modifiers" begin

    @testset "Optional parser" begin
        include("modifiers/optional.jl")
    end

    @testset "withDefault Modifier" begin
        include("modifiers/withDefault.jl")
    end

    @testset "Multiple Modifier" begin
        include("modifiers/multiple.jl")
    end

end

@testset "Integration Tests" begin

    @testset "Argparse" begin
        include("argparse.jl")
    end
end


#=



**Translation Prompt for TypeScript → Julia Unit Tests (Updated with your extra points)**

You are translating a suite of unit tests from **TypeScript** to **Julia**.

***

### Context / Domain Types (use exactly these; include them in your mental model but **do NOT re-define** them unless asked)

```julia
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
```

***

### Required API shape (important)

*   **Do not use method-style calls** (no `parser.parse`, no `parser.complete`).
*   Always use the **free functions** exactly as:
    *   `parse(parser, context::Context)`
    *   `complete(parser, state)`
*   When a TS test calls `parse` **with an argv array**, prefer `argparse` (see “Additional rules”):
    *   `res = argparse(parser, ["-v", "…"])`
    *   If you must construct a context, do:
        *   `ctx = Context(argv_vector, parser.initialState)`
        *   `res = parse(parser, ctx)`
*   For tests that require `optionsTerminated = true`, construct explicitly:
    *   `Context{typeof(state)}(buffer, state, true)`

***

### ErrorTypes.jl usage

Treat all parser results as `Result`/`Option` from **ErrorTypes.jl**.

*   Use:
    *   `is_error(x)` to test failure
    *   `unwrap(x)` to access success payload
    *   `unwrap_error(x)` to access failure payload
*   For TS’s `assertErrorIncludes(result.error, "...")`, write:
    *   `@test occursin("...", string(error_or_result))`
*   Use `nothing` where TS expects `undefined`.

***

### Structural differences to respect

*   `ParseSuccess.consumed` is a **tuple of `String`** in Julia.
    *   Compare with tuple literals, e.g. `("-v",)` or `("--port","8080")`.
    *   Do not compare to `Vector` unless you intentionally convert.
*   `Context.buffer` is `Vector{String}`; compare to `String[]` for empty.
*   Do **not** mutate structs; construct new `Context` values when “updating”.
*   **Option parser value parser position**: `option("--long", "-s", value_parser)` — keep the value parser **at the end** (do **not** reorder).
*   **Accessing fields**: prefer `getproperty(obj, :name)` (not `getfield`).

***

### Style constraints for the translation

*   Do **not** introduce any helper functions or macros in tests (no test helpers).
*   Do **not** mimic TS assertion style; just preserve the logic of what is being checked.
*   Use plain `@test`, `is_error(...)`, `unwrap(...)`, `unwrap_error(...)`, direct property access via `getproperty`, and `occursin(...)`.
*   Keep **one `@testset` per TS `it(...)` block** with the **same description**.
*   When TS checks `Array.isArray(state)`, assert the logically equivalent Julia property (e.g., `state isa AbstractVector`) and length checks as needed.
*   When TS expects `undefined`, assert `=== nothing`.
*   If a TS test manually feeds a completion state, mirror that with `Vector{Result}` values, e.g. `[Ok(true)]` or `[Err("message")]`, unless the parser exposes an exact type; only assert what TS asserts (value or message).

***

### Additional rules (your extra points)

*   When the TS code does `parse(parser, ["list", "of", "strings"])`, **translate to**:
    *   `argparse(parser, ["list", "of", "strings"])`
*   Keep the **value parser at the end** for `option(...)` (do **not** reorder arguments).
*   options `option(...)` with only strings as arguments are to be translated into `flag(...)`
*   any call to `string(...)` is to be translated to `str(...)`
*   Use `getproperty(x, :field)` instead of `getfield(x, :field)` when checking fields.
*   When asserting `ParseSuccess.consumed` for **multiple flags/args**, ensure it’s a **tuple** (e.g., `("-n", "Alice")`), not an array.

***

### Output format

*   Produce **one Julia test file content** (a single code block), ready to save under `test/..._tests.jl`.
*   At the top of the file, include: `using Test`, `using ErrorTypes`, and any needed module imports (assume a placeholder `YourParserModule` if necessary, but keep it **commented**).
*   **Translate exactly** the TS `it(...)` cases provided, **in order**, into `@testset` blocks with the same names.
*   Ensure every test uses the **free-function API**: `parse(parser, context)` and `complete(parser, state)`, and prefer `argparse(parser, argv)` when the TS uses `parse(parser, [ ... ])`.

***

### Examples of common translations

*   **TS**: `const result = parse(parser, ["-v", "-p", "8080"]);`
    **Julia**: `res = argparse(parser, ["-v", "-p", "8080"])`

*   **TS**: `assert.deepEqual(parseResult.consumed, ["-n", "Alice"]);`
    **Julia**: `@test unwrap(res).consumed == ("-n", "Alice")`

*   **TS**: `assert.equal(result.value.verbose, true);`
    **Julia**: `@test getproperty(unwrap(res).next.state, :verbose) == true`

*   **TS**: `parser.parse(context)`
    **Julia**: `res = parse(parser, ctx)`

*   **TS**: `parser.complete(state)`
    **Julia**: `res = complete(parser, state)`

***

### Reminders

*   Always **prefer `argparse`** when TS called `parse` with a literal argv array.
*   For explicit context construction or special flags like `optionsTerminated`, use `Context(...)` as specified.
*   Keep assertions minimal and faithful to what TS checks; avoid extra assumptions.
*   Compare strings and tuples exactly; avoid unintended vector/tuple mismatches.
*   Use `nothing` for `undefined`, and `getproperty` for field access.


=#
