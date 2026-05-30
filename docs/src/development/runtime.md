# Runtime Model

## Big Picture

OptParse is organized around two related but distinct abstractions:

- `AbstractValueParser{T, E}` converts a single raw string token into a value of type `T`, with error type `E`
- `AbstractParser{T, E, S, P, R}` consumes command-line structure and eventually produces a value of type `T`

The high-level split in the source tree is:

- `src/core/`
  - parsing context
  - parse result types
  - structured errors and error rendering
- `src/parsers/valueparsers/`
  - string-to-value parsers such as `str`, `integer`, `choice`, `flt`, `uuid`, `path`
- `src/parsers/primitives/`
  - leaf parser families such as `switch`, `flag`, `option`, `arg`, `command`
- `src/parsers/constructors/`
  - combinators that combine child parsers such as `record`, `or`, `sequence`, `concat`, `combine`
- `src/parsers/modifiers/`
  - wrappers that transform parser behavior, such as `default`, `optional`, `repeated`
- `src/display/`
  - pretty-printing of parser values

The central entrypoints live in `src/entrypoints.jl`:

- `tryoptparse(parser, argv)`
- `optparse(parser, argv)`
- `runparse(parser, argv; ...)`
- `partial(parser)` + `tryoptparse(partial(p), argv)`

And `normalize_argv(argv)` lives in `src/OptParse.jl`.

## `AbstractParser{T,E,S,P,R}` Type Parameters

The core parser abstraction is:

```julia
AbstractParser{T, E, S, P, R}
```

The parameters mean:

- `T`
  - the final value type returned by `complete`
  - equivalently, the success type of `ParseResult{T, E}`
- `E`
  - the error type for this parser family
  - always a `Union` of per-parser error structs (all `<: AbstractParseError`)
  - composed upward: a constructor's `E` includes its own error plus all child errors
- `S`
  - the parser-family-specific state type threaded through `Context{S}`
  - this is the type consumed by `complete(p, state::S)`
- `P`
  - parser-family-specific extra type information
  - for leaf families this is often `Nothing`
  - for wrappers and constructors this is often the child parser type or tuple of child parser types
- `R`
  - the parser priority as a compile-time integer parameter

The invariants are:

- `T` is the semantic output type of the parser
- `E` is the union of all error types this parser family can produce (including child errors)
- `S` is the only state shape that parser family should interact with directly
- `P` should stay concrete so that parser-family-specific code can remain inferable
- `R` is stable for a given parser family instance and drives constructor scheduling

Helper functions expose the same information in code:

```julia
tval(parser_or_type)
terr(parser_or_type)
tstate(parser_or_type)
ptypes(parser_or_type)
priority(parser_or_type)
```

When adding a parser family, think of `S`, `E`, and `R` as part of the parser contract,
not as incidental implementation details.

## Parse Model

OptParse parsing is split into two phases.

### `parse`

The `parse` phase incrementally walks the parser tree while consuming command-line
tokens and updating parser-local state.

Each parser family implements a method shaped like:

```julia
parse(p::SomeParser{T, E, S}, ctx::Context{S})::InnerParseResult{S, E}
```

The result can be:

- `InnerParseSuccess{S}` with:
  - a `Consumed` view of the consumed tokens
  - a next `Context{S}`
  - `counts_as_match::Bool`
- `InnerParseFailure{E}` with:
  - an integer “consumed count” used for choosing better failures
  - an error of type `E`

### `complete`

The `complete` phase collapses the final parser state into the returned value:

```julia
complete(p::SomeParser{T, E, S}, state::S)::ParseResult{T, E}
```

Typical `complete` responsibilities:

- turn successful parser-local state into the final user-facing value
- enforce completion-time invariants, such as:
  - “required flag was never matched”
  - “repeated matched fewer than `min` times”
  - “one child parser failed to complete inside a constructor”
- add parser-specific error context when resurfacing child failures

### Why the split exists

This split is the key to the package design:

- `parse` focuses on token flow and structural matching
- `complete` focuses on final validity and value extraction

That separation keeps combinators composable and makes `parse, don't validate`
fit naturally into the implementation.

## Parser State

Parser state is intentionally a parser-family implementation detail.

A parser family should only ever interact with *its own* state shape. For example:

- `ArgGate` works with `GateState`
- `ArgOption` works with `OptionState{T}`
- `ArgCommand` works with `CommandState{PState}`
- `ModMultiple` works with `MultipleState{S}`

This is why tight `parse` / `complete` signatures matter so much: they enforce
the rule that a parser family only operates on its own state.

In practice, state shape should usually mirror the macro-state the parser can be in.
Typical examples:

- a switch or required flag has states like:
  - not matched yet
  - matched successfully
  - failed to complete because it never matched
- a command has states like:
  - command token not matched yet
  - command matched, inner parser not started yet
  - command matched, inner parser started and has child state
- a repetition has states like:
  - zero repetitions matched
  - one or more repetitions matched, each with its own child state snapshot

This does not mean every parser needs an explicit enum for those macro-states.
It means the chosen state representation should make those states obvious and easy
to reason about.

Good examples already in the codebase are:

```julia
const GateState = ParseResult{Bool, ArgGateError}
const OptionState{T, E} = ParseResult{T, E}
const ArgumentState{T, E} = Option{ParseResult{T, E}}
const ConstantState{X} = Val{X}
const CommandState{S} = Option{Option{S}}
const MultipleState{S} = Vector{S}
const WithDefaultState{S} = Option{S}
const ObjectState{L, P} = NamedTuple{L, P}
const OrState{U} = Option{InnerOrState{U}}
```

Those are implementation details, but they encode the parser family’s conceptual
state machine.

## Concrete Parser Trees And Why State Signatures Matter

The parser tree is now made of concrete `AbstractParser` family nodes. Internal
parser fields should stay parametric and concrete, rather than erasing children
to abstract parser types.

One important consequence is that parser families must still constrain their
`parse` and `complete` signatures to their real state invariants.

For example:

```julia
function parse(p::ArgOption{T, E, OptionState{T, E}}, ctx::Context{OptionState{T, E}})::InnerParseResult{OptionState{T, E}, E} where {T, E}
```

is better than a looser:

```julia
function parse(p::ArgOption, ctx::Context)
```

because the tight signature:

- documents the actual invariant of the parser family
- avoids impossible parser-family instantiations surviving too long in inference
- gives JET less nonsense to analyze
- makes trimming behavior much more predictable

### Child parser state invariants

Wrappers and constructors have an extra invariant: their child parser type must
remain tied to the child state they pass around.

It is not enough for the constructor to build only valid values. The method
signature must also express the relationship, otherwise inference can still
consider impossible child parser / child state combinations.

For a transparent wrapper whose state is exactly the child state, write methods
like:

```julia
function parse(
    p::ModHelp{T, E, S, P, _R},
    ctx::Context{S},
)::InnerParseResult{S, E} where {T, E, S, _R, P <: AbstractParser{<:Any, <:Any, S}}
```

The important part is:

```julia
P <: AbstractParser{<:Any, <:Any, S}
```

That tells inference that the wrapped child parser also operates on state `S`.

For a wrapper whose state contains a child state, bind the child parser to the
inner state instead:

```julia
function parse(
    p::ModWithDefault{T, E, WithDefaultState{S}, P, _R},
    ctx::Context{WithDefaultState{S}},
)::InnerParseResult{WithDefaultState{S}, E} where {T, E, S, _R, P <: AbstractParser{<:Any, <:Any, S}}
```

Here the wrapper state is `WithDefaultState{S}`, but the wrapped parser operates
on `S`. The signature must make that distinction explicit.

This applies to `parse`, `complete`, `usage`, `focused_usage`, and any other
method that delegates to the child parser while relying on a particular child
state shape.

## `Context`

`Context{S}` lives in `src/core/context.jl`.

Conceptually, `Context` is the current parser execution frame:

- it says which normalized argv buffer is being parsed
- where the parser currently is in that buffer
- what the parser-family-local state currently is
- whether global option parsing has already been terminated by `--`

It carries:

- `buffer::Vector{String}`
- `pos::Int`
- `state::S`
- `usage::UsageNode`
- `optionsTerminated::Bool`

The important point is that `Context` is parameterized by the parser state type.
That means “update the state” is not merely a field assignment. It is often an
inference checkpoint.

A parser should only ever interact with `Context` through the helper functions and
centralized checkpoints in `src/core/context.jl`.

In particular, parser-family code should avoid rebuilding contexts ad hoc unless
there is a very good reason. The helper API keeps context updates:

- explicit
- type-stable
- grep-friendly
- consistent across parser families

The main helpers are:

- `ctx_with_state(ctx, s)`
- `ctx_restate(ctx, s)`
- `widen_state(::Type, ctx)`
- `widen_restate(::Type, ctx, s)`
- `ctx_with_options_terminated(ctx, flag)`
- `ctx_hasmore`, `ctx_hasnone`, `ctx_peek`, `ctx_remaining`, `ctx_length`
- `consume(ctx, n)`

### Flat context access vs optics

Current guidance:

- use direct helpers or centralized checkpoints for `Context`
- use optics where nested immutable state updates are actually needed

This is why:

- `Context` updates go through helpers like `ctx_with_state` and `consume`
- nested constructor state updates still use `PropertyLens` / `IndexLens`

As a rule of thumb:

- for `Context`, use the helper API
- for nested constructor state stored inside `Context.state`, optics are still appropriate

## `Consumed`

`Consumed` lives in `src/core/parseresult.jl`.

It is a cheap view of consumed tokens:

- it stores the shared input buffer
- it stores one or more ranges into that buffer
- it behaves like an `AbstractVector{String}`

This avoids eagerly materializing consumed token vectors while still making it easy to:

- inspect consumed tokens in tests
- merge consumptions from nested combinators
- preserve a precise token view when bundled short flags are expanded

Important helpers:

- `consumed_empty(ctx)`
- `merge(::Vector{Consumed})`
- `as_vector(consumed)`
- `as_tuple(consumed)`

## `InnerParseSuccess` and `InnerParseFailure`

These also live in `src/core/parseresult.jl`.

`InnerParseSuccess{S}` carries:

- `consumed::Consumed`
- `next::Context{S}`
- `counts_as_match::Bool`

`InnerParseFailure{E}` carries:

- `consumed::Int` (number of tokens consumed before failure)
- `error::E` (the concrete error value)

Together they form:

```julia
const InnerParseResult{S, E} = Result{InnerParseSuccess{S}, InnerParseFailure{E}}
```

`counts_as_match` is subtle and important.

It exists because not every successful token consumption should count as a
semantic parser match. The main current example is `--`:

- a primitive parser may consume `--`
- that should update `optionsTerminated`
- but it should not satisfy an `or` branch or one slot of a `sequence`

So:

- “consumed input” and “counts as a semantic match” are intentionally different concepts

Helpers:

- `innerOk(ctx, n; nextctx=..., counts_as_match=true)`
- `innerOk(nextctx, consumed, counts_as_match=true)`
- `innerErr(ctx, perr; consumed=0)`

## Error Model

Structured errors live in `src/core/errors.jl`.

The core pieces are:

- `AbstractParseError`
  - abstract base type for all per-parser error structs
- `ParseError{E}`
  - `@wrapped` union container; `E` is always a `Union` of concrete error struct types
  - `render_error(io, err::ParseError)` dispatches via `@unionsplit`
- Per-parser error structs (all `<: AbstractParseError`)
  - `MainError` — top-level parsing errors (MAIN_NoProgress, MAIN_UnexpectedToken)
  - `ConstrObjectError` — record errors (OBJECT_UnexpectedToken, OBJECT_EndOfInput, OBJECT_MaxIter)
  - `ConstrOrError` — or parser errors
  - `ModMultipleError` — repeated errors (MULTIPLE_TooFew, MULTIPLE_TooMany)
  - `ArgGateError`, `ArgOptionError`, `ArgArgumentError`, `ArgCommandError` — primitive errors
  - `StringValError`, `IntegerValError`, `FloatValError`, etc. — value parser errors
- `ParseException{P, E}`
  - thrown by `optparse` in non-juliac runtime mode
  - wraps parser, argv, and `ParseError{E}`

Every parser family or value parser family should define:

- its own error struct `<: AbstractParseError` with an `@enum` code field
- a `render_error(io::IO, err::MyError)` method

Error type composition happens automatically through the `E` type parameter: a constructor's
`E` is `Union{OwnError, child_errors...}`.

The `validate(::Type{E}) where {E <: AbstractParseError}` helper verifies that
`render_error` is implemented for a given error type.
