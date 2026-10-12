# Inference and trimming

OptParse supports a dynamic path for interactive Julia and a static path for
compiled applications. Both paths use the same parser definitions and parsing semantics.

!!! warning "Date/time parsers are not trimmable"
    `dateformat`, `isodate`, and `isodatetime` do not support trimming because
    their underlying parsing mechanism contains type instabilities.
    Setting `juliac=true` does not remove this limitation.
    These parsers work in normal Julia applications.

## Specialization modes

The compile-time `juliac` preference selects the implementation:

| Mode | Implementation | Purpose |
|------|----------------|---------|
| `juliac=false` (default) | Runtime loops and specialization barriers | Reduce compilation cost during interactive use. |
| `juliac=true` | Fully specialized methods and generated loops | Keep parser operations inferable for trimming. |

The parser determines its output type in both modes. The dynamic path intentionally
uses runtime dispatch in complex constructors; it does not promise full inference
through every parsing operation.

To enable static mode in an application environment:

```julia
using OptParse, Preferences
set_preferences!(OptParse, "juliac" => true)
```

Restart Julia after changing this preference. It is read when OptParse loads,
not for each parsing call. Use `false` to restore dynamic mode.

The preference changes specialization, not parse-error handling.
`optparse` prints parse errors and returns `nothing` in both modes.

### Source organization

Each constructor has a shared API file and two implementation files.
For example:

- `src/parsers/constructors/record.jl`: shared methods and public wrappers
- `src/parsers/constructors/static/record.jl`: generated implementations
- `src/parsers/constructors/dynamic/record.jl`: runtime-loop implementations

`constructors.jl` selects these files with `@static if juliac`.
Use compile-time selection for mode-specific implementations, not a runtime `if`.

### `@autospecialize`

`src/utils.jl` defines the internal `@autospecialize` macro.
In static mode, it preserves a method's type parameters and annotations.
In dynamic mode, it adds `@nospecialize` for selected arguments and recovers
their type parameters inside the method.

Keep the specialization barrier at these wrappers. Do not add barriers inside
core methods that need full inference in static mode.
Avoid sort closures that capture parser tuple types in dynamic implementations.
Extract priorities into a plain vector before sorting.

## Test placement

Functional tests run in both modes. The test project sets `juliac=true`.
`test/runtests.jl` also launches a subprocess for dynamic-mode tests.

- Keep value-parser and primitive-constructor `@test_opt` checks with their unit tests
  when those checks pass in both modes.
- Put inference checks for complex `parse`, `complete`, and `optparse` operations
  in `test/unit/typestability.jl`. That file runs only in static mode.
- Do not require full inference from intentional dynamic-mode dispatch.
- Use `test/trim/` integration tests to check compiled executables.

For a new parser family, cover constructor behavior, successful parsing,
parse failures, and completion failures. Add static-mode inference checks for
its composition with other parsers.

## State and child-parser invariants

Inference depends on the relationship between the parser, its state, and its children.
Keep child parser fields concrete and parametric. Preserve the state parameter
through `Context` helpers.

For example, an option parser constrains its state to the value type and
value-parser error type:

```julia
function parse(
    p::ArgOption{T, E, S},
    ctx::Context{S},
) where {T, E, IE <: E, S <: OptionState{T, IE}}
    # Parser-family implementation.
end
```

These signatures are implementation sketches, not definitions to copy into user code.
A signature such as `parse(p::ArgOption, ctx::Context)` loses the state relationship
and leaves inference free to consider invalid parser/state combinations.

For a transparent wrapper, bind the child parser to the same state:

```julia
function parse(
    p::ModHelp{T, E, S, P},
    ctx::Context{S},
) where {T, E, S, P <: AbstractParser{T, E, S}}
    # Delegate to the child parser.
end
```

For a wrapper with nested state, bind the child to the inner state:

```julia
function complete(
    p::ModWithDefault{T, E, WithDefaultState{S}, P},
    state::WithDefaultState{S},
) where {T, E, S, P <: AbstractParser{<:Any, <:Any, S}}
    # Complete the child state or return the default.
end
```

The wrapper uses `WithDefaultState{S}`. Its child uses `S`.
Apply this relationship to methods that delegate to the child parser.

## Investigate inference failures

If JET reports a dispatch problem, examine these points before adding local assertions:

1. Does each parser family operate only on its own state shape?
2. Do wrapper constraints tie child parsers to the states they receive?
3. Do context updates preserve `Context{S}` through its helper API?
4. Does a helper erase type information or create an abstract container?
5. Does the test run in the intended specialization mode?

Constructor validation alone does not express these invariants to inference.
Method signatures must also describe the relationships used by the implementation.
