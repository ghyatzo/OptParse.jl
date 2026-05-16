# AGENTS.md — OptParse.jl

## Project Overview

OptParse.jl is a type-stable, composable CLI argument parser for Julia, designed to support `juliac` trimming. Parsers form a tree: leaf nodes (primitives) do actual parsing, intermediate nodes (constructors, modifiers) compose them. Parsing is two-phase: `parse` matches input and updates state, `complete` extracts the final typed value.

**Julia 1.12+ required.** Uses workspaces (`[workspace]` in root Project.toml).

## Architecture

### Type Hierarchy

**`AbstractParser{T, S, p, P}`** — four type parameters:
- `T`: output value type, `S`: internal state type, `p`: priority (Int, controls ordering in constructors), `P`: child parser types (for trimming reachability).

**`AbstractValueParser{T}`** — callable parsers that convert a single string token into `ParseResult{T}`.

### Parser Categories

- **Value parsers** (`src/parsers/valueparsers/`): `StringVal`, `IntegerVal`, `FloatVal`, `Choice`, `UUIDVal`, `PathVal`.
- **Primitives** (`src/parsers/primitives/`): `ArgOption`, `ArgGate` (flags/switches), `ArgArgument`, `ArgCommand`, `ArgConstant`.
- **Constructors** (`src/parsers/constructors/`): `ConstrObject` (record/named fields), `ConstrTuple` (sequence/positional), `ConstrOr` (alternatives). Also `combine` (`_merge`) and `concat` (`_concat`).
- **Modifiers** (`src/parsers/modifiers/`): `ModWithDefault`, `ModMultiple` (repeated), `ModConstruct`, `ModConstructExact`, `ModHelp`.

### Entrypoints (`src/entrypoints.jl` + `src/OptParse.jl`)

- `tryoptparse(parser, argv)` → `ParseResult{T}` (non-throwing)
- `optparse(parser, argv)` → `T | nothing` (prints error to stderr)
- `runparse(parser, argv; ...)` → application-level with built-in `--help` and help subcommands
- `build_help_doc(parser, argv)` → `HelpDoc` (focused help document for a given argv context)
- `generate_help(parser, argv)` / `print_help(io, parser, argv)` — render help text

### Core Subsystems (`src/core/`)

- **Context** (`context.jl`): `Context{S}` carries buffer, position, state accumulator, usage node, and optionsTerminated flag. Immutable — state transitions create new contexts via `ctx_with_state`, `ctx_restate`, `widen_state`.
- **Parse results** (`parseresult.jl`): `ParseResult{T} = Result{T, ParseError}`. Inner parsing uses `InnerParseResult{S} = Result{InnerParseSuccess{S}, InnerParseFailure}` which carries consumed tokens and next context. Also defines `Consumed` (lazy view of consumed tokens).
- **Errors** (`errors.jl`): `ParseError` struct with `ErrorDomain` enum (one variant per parser type), `UInt8` error code, token, detail, and trace (`Vector{ErrorSite}`). Rendering via `render_error_payload` dispatches on domain enum. Each parser file defines its own `@enum` of error codes and `*_render_error` function.
- **Usage AST** (`usage/nodes.jl`): `UsageNode` with `UsageKind` enum (`USAGE_Flag`, `USAGE_Option`, `USAGE_Argument`, `USAGE_Command`, `USAGE_Object`, `USAGE_Tuple`, `USAGE_Alternative`, `USAGE_Optional`, `USAGE_Repeat`, `USAGE_Hidden`, `USAGE_Empty`). Constructors: `UsageFlag`, `UsageOption`, `UsageArgument`, etc.
- **Usage rendering** (`usage/render_usage.jl`): `render_usage(node; style=:compact)` renders a `UsageNode` tree to text. Supports `:compact` and `:expanded` styles. Uses traits in `usage/traits.jl` for layout decisions (collapsing optional options, stacking alternatives).
- **Help** (`help/helpdoc.jl`): `HelpInfo` (brief, description, footer, hidden), `HelpEntry` (usage + info), `HelpDoc` (prefix, usage, info, entries). `render_helpdoc` groups entries by kind (Commands, Arguments, Options, Other).
- **Help overlay** (`parsers/parser.jl` top): `OverlayContext` wraps `HelpInfo`. Help info is node-local (not inherited by children via `descend_child`). `ModHelp` populates it.

### Display (`src/display/parser_show.jl`)

`Base.show` delegates to `show_compact` (one-line) and `show_pretty` (tree with indentation). Each concrete type has specific `show_compact`/`show_pretty` methods. Generic fallbacks exist on `AbstractValueParser` and `AbstractParser`.

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
| `src/OptParse.jl` | Module entry, loads `juliac` preference, public API wrappers (`build_help_doc`, `generate_help`, `runparse`) |
| `src/utils.jl` | `@autospecialize` macro, tuple sort utilities |
| `src/entrypoints.jl` | Core entrypoints (`optparse`, `tryoptparse`), parsing loop |
| `src/parsers/parser.jl` | `OverlayContext`, then includes all parser subdirectories |
| `src/parsers/constructors/constructors.jl` | Constructor includes, static/dynamic split, `_usage_children`, `_merge`, `_concat` |
| `src/core/context.jl` | `Context{S}` struct and helpers |
| `src/core/parseresult.jl` | `Consumed`, `InnerParseResult`, `ParseResult`, result constructors |
| `src/core/errors.jl` | `ParseError`, `ErrorDomain` enum, `render_error`/`render_error_payload` |
| `src/core/usage/` | `UsageNode` AST (`nodes.jl`), rendering traits (`traits.jl`), text rendering (`render_usage.jl`) |
| `src/core/help/` | `HelpInfo`, `HelpEntry`, `HelpDoc` (`helpdoc.jl`), `render_helpdoc` (`render_help.jl`) |
| `src/display/parser_show.jl` | `show_compact`/`show_pretty` for all parser and value parser types |

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
| `parse` | `(p, ctx::Context{S}) → InnerParseResult{S}` | Match tokens, update state |
| `complete` | `(p, state::S) → ParseResult{T}` | Extract final value from state |
| `usage` | `(p) → UsageNode` | Generate usage AST node |
| `helpentries` | `(p, rt::OverlayContext) → Vector{HelpEntry}` | Generate help listing entries |
| `focused_helpdoc` | `(p, ctx, prefix, rt) → HelpDoc` | Build scoped help document |

Each parser also defines `show_compact(io, p)` and `show_pretty(io, p, indent)` for display.

Every concrete value parser is callable: `(v::AbstractValueParser{T})(input::String) → ParseResult{T}`.

### Error Pattern (per parser)

Each parser file defines: an `@enum` of error codes, a factory function (calls `mkerror`), and a render function. These are wired together in `render_error_payload` in `src/core/errors.jl` via an if/elseif chain on the `ErrorDomain` enum.

## Development Guidelines

- The specialization barrier is at `@autospecialize` wrappers, not inside core functions.
- When adding dynamic-path code that intentionally uses runtime dispatch, do NOT add `@test_opt` for it — or put it in `unit/typestability.jl` (juliac-only).
- Sort closures capturing tuple types cause specialization. Extract values into `Vector` first.
- `@static if juliac` blocks select code paths at compile time — not `if juliac` (which is runtime).
