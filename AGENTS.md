# AGENTS.md — OptParse.jl

## Project Overview

OptParse.jl is a type-stable, composable CLI argument parser for Julia, designed to support `juliac` trimming. Parsers form a tree: leaf nodes (primitives) do actual parsing, intermediate nodes (constructors, modifiers) compose them. Parsing is two-phase: `parse` matches input and updates state, `complete` extracts the final typed value.

**Julia 1.12+ required.** Uses workspaces (`[workspace]` in root Project.toml).

## Architecture

### Parser Hierarchy

- **Value parsers** (`src/parsers/valueparsers/`): Parse individual tokens into values (string, integer, float, uuid, choice, path).
- **Primitives** (`src/parsers/primitives/`): Leaf parsers that consume CLI tokens — `option`, `flag/switch (gate)`, `arg`, `command`, `constant`.
- **Constructors** (`src/parsers/constructors/`): Compose primitives into structures — `record` (named fields), `tuple/sequence` (positional), `or` (alternatives). Also `combine` and `concat`.
- **Modifiers** (`src/parsers/modifiers/`): Wrap parsers to alter behavior — `default`, `optional`, `repeated`, `construct`, `help`.
- **Entrypoints** (`src/entrypoints.jl`): `optparse`, `tryoptparse`, `render_error`, `render_helpdoc`.

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

`CommandState{X} = Option{Option{X}}` and `OrState{U} = Option{InnerOrState{U}}` are type aliases. They are transparent at runtime (Julia expands them), so `typeof(x).parameters[1]` gives the expanded form, not the alias. Accessor functions like `_inner_state(::CommandState{X})` recover the inner type parameter.

## Key Files

| Path | Role |
|------|------|
| `src/OptParse.jl` | Module entry, loads `juliac` preference |
| `src/utils.jl` | `@autospecialize` macro, tuple sort utilities |
| `src/entrypoints.jl` | Public API (`optparse`, `tryoptparse`) |
| `src/parsers/parser.jl` | `AbstractParser` type hierarchy |
| `src/parsers/constructors/constructors.jl` | Constructor includes, `_usage_children` split |
| `src/core/` | Context, state, error types, usage AST, display |

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

## Development Guidelines

- The specialization barrier is at `@autospecialize` wrappers, not inside core functions.
- When adding dynamic-path code that intentionally uses runtime dispatch, do NOT add `@test_opt` for it — or put it in `unit/typestability.jl` (juliac-only).
- Sort closures capturing tuple types cause specialization. Extract values into `Vector` first.
- `@static if juliac` blocks select code paths at compile time — not `if juliac` (which is runtime).
