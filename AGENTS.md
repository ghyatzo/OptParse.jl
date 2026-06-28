# AGENTS.md — OptParse.jl

## Project Overview

OptParse.jl is a type-stable, composable CLI argument parser for Julia, designed to support `juliac` trimming. Parsers form a tree: leaf nodes (primitives) do actual parsing, intermediate nodes (constructors, modifiers) compose them. Parsing is two-phase: `parse` matches input and updates state, `complete` extracts the final typed value.

**Julia 1.12+ required.** Uses workspaces (`[workspace]` in root Project.toml).

## Architecture

### Type Hierarchy

**`AbstractParser{T, E, S, P, R}`** — five type parameters:
- `T`: output value type, `E`: error type (union of per-parser errors), `S`: internal state type, `P`: child parser types (for trimming reachability), `R`: priority/rank (Int, controls ordering in constructors).

**`AbstractValueParser{T, E}`** — callable parsers that convert a single string token into `ParseResult{T, E}`.

**`AbstractLiftedParser`** — supertype automatically applied to all `@parser` structs. Enables type-based entrypoints (`optparse(MyType, argv)`, `lift(::Type{MyType})`).

### Parser Categories

- **Value parsers** (`src/parsers/valueparsers/`): `StringVal`, `IntegerVal`, `FloatVal`, `Choice`, `UUIDVal`, `PathVal`. Extension: `IdentifierVal` (via `FastIdentifiersExt`).
- **Primitives** (`src/parsers/primitives/`): `ArgOption`, `ArgGate` (flags/switches), `ArgArgument`, `ArgCommand`, `ArgConstant`.
- **Constructors** (`src/parsers/constructors/`): `ConstrObject` (record/named fields), `ConstrTuple` (sequence/positional), `ConstrOr` (alternatives). Also `combine` (`_merge`) and `concat` (`_concat`).
- **Modifiers** (`src/parsers/modifiers/`): `ModWithDefault`, `ModMultiple` (repeated/many/many1), `ModConstruct`, `ModConstructExact`, `ModHelp`.
- **Pseudo-parsers** (`src/entrypoints.jl`): `Partial{T, E, S, P}` — wraps a parser for partial consumption (passthrough).

### Entrypoints (`src/entrypoints.jl` + `src/OptParse.jl`)

- `tryoptparse(parser, argv)` → `ParseResult{T, Union{E, MainError}}` (non-throwing)
- `optparse(parser, argv)` → `T | nothing` (prints error to stderr)
- `runparse(parser, argv; ...)` → application-level with built-in `--help` and help subcommands
- `partial(parser)` → wraps parser for partial consumption; `tryoptparse(partial(p), argv)` returns `(value, remaining)`
- `lift(::Type{T})` → retrieves the parser associated with an `@parser` struct type
- `optparse(::Type{T}, argv)`, `tryoptparse(::Type{T}, argv)`, `runparse(::Type{T}, argv)` — type-based entrypoint variants for `T<:AbstractLiftedParser`
- `build_help_doc(parser, argv)` → `HelpDoc` (focused help document for a given argv context)
- `generate_help(parser, argv)` / `print_help(io, parser, argv)` — render help text

### Core Subsystems (`src/core/`)

- **Context** (`context.jl`): `Context{S}` carries buffer, position, state accumulator, usage node, and optionsTerminated flag. Immutable — state transitions create new contexts via `ctx_with_state`, `ctx_restate`, `widen_state`.
- **Parse results** (`parseresult.jl`): `ParseResult{T, E} = Result{T, E}`. Inner parsing uses `InnerParseResult{S, E} = Result{InnerParseSuccess{S}, InnerParseFailure{E}}` which carries consumed tokens and next context. Also defines `Consumed` (lazy view of consumed tokens).
- **Errors** (`errors.jl`): `ParseError{E}` is a `@wrapped` union container. Each parser family defines its own `<: AbstractParseError` struct (e.g. `MainError`, `ConstrObjectError`, `ModMultipleError`, `StringValError`). Rendering dispatches via `render_error(io, err)` on concrete error types. `ParseException{P, E}` wraps a `ParseError{E}` with the parser and argv for `showerror`.
- **Usage AST** (`usage/nodes.jl`): `UsageNode` with `UsageKind` enum (`USAGE_Flag`, `USAGE_Option`, `USAGE_Argument`, `USAGE_Command`, `USAGE_Object`, `USAGE_Tuple`, `USAGE_Alternative`, `USAGE_Optional`, `USAGE_Repeat`, `USAGE_Hidden`, `USAGE_Empty`). Constructors: `UsageFlag`, `UsageOption`, `UsageArgument`, etc.
- **Usage rendering** (`usage/render_usage.jl`): `render_usage(node; style=:compact)` renders a `UsageNode` tree to text. Supports `:compact` and `:expanded` styles. Uses traits in `usage/traits.jl` for layout decisions (collapsing optional options, stacking alternatives).
- **Help** (`help/helpdoc.jl`): `HelpInfo` (brief, description, footer, hidden), `HelpEntry` (usage + info), `HelpDoc` (prefix, usage, info, entries). `render_helpdoc` groups entries by kind (Commands, Arguments, Options, Other).
- **Help overlay** (`parsers/parser.jl` top): `OverlayContext` wraps `HelpInfo`. Help info is node-local (not inherited by children via `descend_child`). `ModHelp` populates it.

### Display (`src/display/parser_show.jl`)

Three extension points for display:
- `Base.show(io, p)` — compact inline representation
- `show_children(p)` — returns `Vector{Pair{String, <:AbstractParser}}` for tree display, or `nothing` for leaves
- `printnode(io, p)` — tree header label (defaults to `show`)

The REPL uses `MIME"text/plain"` to render a full tree with connectors (`├─`, `└─`, `│`).

### The `juliac` Preference

`const juliac = @load_preference("juliac", false)` in `OptParse.jl`. This compile-time constant controls two code paths:

- **`juliac=true` (static/trim mode):** Full type specialization. `@generated` functions unroll loops over parser fields. Required for `juliac` trimming.
- **`juliac=false` (dynamic/interactive mode):** `@nospecialize` wrappers prevent specialization explosion, reducing TTFX. Runtime loops replace unrolled code.

### Static/Dynamic Split

Constructors have three files each (e.g., for `record`):
- `record.jl` — Base: public API wrappers (`parse`, `complete`, `helpentries`, `focused_helpdoc`, `usage`) and shared logic.
- `static/record.jl` — `@generated` implementations with unrolled loops for full type inference.
- `dynamic/record.jl` — `@nospecialize` implementations with runtime loops.

Selected via `@static if juliac` in `constructors.jl`.

### `@autospecialize` Macro

Defined in `src/utils.jl`. Wraps function definitions to conditionally despecialize:
- In `juliac=true`: passthrough (identity).
- In `juliac=false`: strips `where` type parameters from targeted arguments, adds `@nospecialize`, and injects `typeof(arg).parameters[i]` extraction into the body.

Usage: `@autospecialize target_arg function f(target_arg::SomeType{T}, other_arg) where {T} ... end`

### Type Aliases

State aliases per parser family:
- `GateState = ParseResult{Bool, ArgGateError}`
- `OptionState{X, E} = ParseResult{X, E}`
- `ArgumentState{X, E} = Option{ParseResult{X, E}}`
- `ConstantState{X} = Val{X}`
- `CommandState{X} = Option{Option{X}}`
- `ObjectState{L, P} = NamedTuple{L, P}`
- `OrState{U} = Option{InnerOrState{U}}`
- `MultipleState{X} = Vector{X}`
- `WithDefaultState{X} = Option{X}`

These are transparent at runtime (Julia expands them), so `typeof(x).parameters[1]` gives the expanded form, not the alias.

## Key Files

| Path | Role |
|------|------|
| `src/OptParse.jl` | Module entry, loads `juliac` preference, `AbstractParser{T,E,S,P,R}`, `AbstractValueParser{T,E}`, `AbstractLiftedParser`, exports, `normalize_argv` |
| `src/utils.jl` | `@autospecialize` macro, tuple sort utilities |
| `src/entrypoints.jl` | Core entrypoints (`optparse`, `tryoptparse`, `runparse`, `partial`), `lift`, type-based entrypoints, parsing loop |
| `src/parsers/parser.jl` | `OverlayContext`, `validate`, public API constructors (all exported parser functions), `@parser` macro, then includes all parser subdirectories |
| `src/parsers/constructors/constructors.jl` | Constructor includes, static/dynamic split, `_usage_children`, `_merge`, `_concat` |
| `src/core/context.jl` | `Context{S}` struct and helpers |
| `src/core/parseresult.jl` | `Consumed`, `InnerParseSuccess{S}`, `InnerParseFailure{E}`, `InnerParseResult{S, E}`, result constructors |
| `src/core/errors.jl` | `AbstractParseError`, `ParseError{E}` (@wrapped union), `MainError`, `ParseException`, `render_error` |
| `src/core/usage/` | `UsageNode` AST (`nodes.jl`), rendering traits (`traits.jl`), text rendering (`render_usage.jl`) |
| `src/core/help/` | `HelpInfo`, `HelpEntry`, `HelpDoc` (`helpdoc.jl`), `render_helpdoc` (`render_help.jl`) |
| `src/display/parser_show.jl` | `show_children`/`printnode` display interface, tree printer |
| `ext/FastIdentifiersExt.jl` | `IdentifierVal{T}` value parser for FastIdentifiers-based types |

## Testing

Tests live in `test/`. The test project (`test/Project.toml`) sets `juliac=true`.

### Test Structure

- `runtests.jl` — Orchestrator: runs inner tests in-process (juliac=true), type stability tests (juliac-only), then spawns subprocess for juliac=false run. Also runs Trimming and Aqua tests.
- `runtests_inner.jl` — All functional tests (both modes) + `@autospecialize` macro tests.
- `unit/typestability.jl` — `@test_opt` tests for complex parsers (juliac=true only).
- `trim/` — Trimming tests that compile executables with `JuliaC`.

### Running Tests

```bash
# Full suite (both modes + trimming + aqua):
julia --project -e 'using Pkg; Pkg.test()'

# Inner tests only (fast, single mode):
julia --project=test test/runtests_inner.jl
```

### JET `@test_opt`

Used to verify type stability. Unconditional `@test_opt` calls (value parsers, primitive constructors) should pass in both modes. Complex parser `@test_opt` (parse/complete/optparse on constructors) lives in `unit/typestability.jl` and only runs with `juliac=true`.

## Per-Parser Interface Methods

Every concrete parser implements these methods (dispatch on concrete type):

| Method | Signature | Purpose |
|--------|-----------|---------|
| `parse` | `(p, ctx::Context{S}) → InnerParseResult{S, E}` | Match tokens, update state |
| `complete` | `(p, state::S) → ParseResult{T, E}` | Extract final value from state |
| `usage` | `(p) → UsageNode` | Generate usage AST node |
| `helpentries` | `(p, rt::OverlayContext) → Vector{HelpEntry}` | Generate help listing entries |
| `focused_helpdoc` | `(p, ctx, prefix, rt) → HelpDoc` | Build scoped help document |

Each parser also defines `show_children(p)` and optionally `printnode(io, p)` for display.

Every concrete value parser is callable: `(v::AbstractValueParser{T, E})(input::String) → ParseResult{T, E}`.

### Error Pattern (per parser)

Each parser file defines: a concrete struct `<: AbstractParseError` with an `@enum` error-code field, a `render_error(io, err)` method. The error struct is composed into the parser's `E` type parameter as a union. `ParseError{E}` wraps the union for uniform handling via `@unionsplit`.

### Interface Validation

`validate(p::AbstractParser)` checks at runtime that a concrete parser type implements the required methods. `validate(::Type{E}) where {E <: AbstractParseError}` checks that `render_error` is defined for an error type.

## Development Guidelines

- The specialization barrier is at `@autospecialize` wrappers, not inside core functions.
- When adding dynamic-path code that intentionally uses runtime dispatch, do NOT add `@test_opt` for it — or put it in `unit/typestability.jl` (juliac-only).
- Sort closures capturing tuple types cause specialization. Extract values into `Vector` first.
- `@static if juliac` blocks select code paths at compile time — not `if juliac` (which is runtime).
