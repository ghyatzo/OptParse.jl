# Release Notes (unreleased)

Tracking user-facing changes for the next release.

## New Features

### `partial` — pass-through parsing
Wrap any parser with `partial(p)` to consume only the arguments it recognizes
and return the rest as a vector. Ideal for wrapper CLIs that forward unknown
flags to child programs. Only `tryoptparse` is supported (no throwing variant) —
use `ErrorTypes` to inspect the result.

```julia
using ErrorTypes: is_error, unwrap

wrapper = partial(record(; verbose = flag("-v"), config = optional(option("-c", str()))))
result = tryoptparse(wrapper, ["-v", "--child-flag", "file"])
# Ok(((verbose = true, config = nothing), ["--child-flag", "file"]))
value, remaining = unwrap(result)
```

### `record` keyword syntax
`record` now also accepts keyword arguments directly, avoiding the inner tuple:

```julia
record(; name = option("-n", str()), port = option("-p", integer()))
```

The named-tuple form `record((name = ..., port = ...))` still works.

### FastIdentifiers extension
Loading `FastIdentifiers` alongside `OptParse` provides an `identifier(Type)`
value parser for structured-identifier types (with checksum validation).

### `lift` and type-based entrypoints
`@parser struct Config ... end` now makes `Config <: AbstractLiftedParser`. You
can call `optparse(Config, args)`, `tryoptparse(Config, args)`, and
`runparse(Config, args; ...)` directly without keeping a parser binding.
`lift(Config)` retrieves the underlying parser for composition (e.g.
`command("status", lift(StatusCmd))`).

### `@description` and `@footer` markers in `@parser`
Parser-level description and footer are now written with explicit `@description`
and `@footer` markers inside the struct body, replacing the old positional-string
convention. Bare strings are now reserved for field briefs.

### Interface validation
`validate(parser)` checks at runtime that a parser correctly implements the
full `AbstractParser` interface. `validate(valueparser)` does the same for
`AbstractValueParser`, and `validate(ErrorType)` verifies that an
`AbstractParseError` subtype defines `render_error`. Useful during development
of custom parsers.

## Improvements

### User-extensible parser and value-parser interfaces
Both `AbstractParser` and `AbstractValueParser` are now first-class extension
points with a documented, minimal interface and a `validate` helper that checks
implementations at runtime.

- **`AbstractParser{T, E, S, P, R}`** — implement `parse`, `complete`, `usage`,
  `helpentries`, and `focused_helpdoc`; compose into larger trees via the
  existing constructors/modifiers. `validate(parser)` reports any missing
  methods.
- **`AbstractValueParser{T, E}`** — implement a callable
  `(v)(input::String) → ParseResult{T, E}` and optionally `usage_annotations(v)`
  to contribute help annotations (e.g. `choice` surfaces `choices: …`).
  `validate(valueparser)` checks the contract.
- **`AbstractParseError`** — per-parser concrete error structs with a
  `render_error(io, err)` method; `validate(ErrorType)` verifies rendering is
  defined.
- **Display** — `show_children` and `printnode` provide opt-in tree rendering
  for custom parser and value-parser types in the REPL.

The built-in value parsers (`str`, `choice`, `integer`, `flt`, `uuid`, `path`),
primitives, constructors, and modifiers are all instances of these interfaces,
so third-party extensions sit at the same level as the bundled ones.

### Help layout with annotations
Help entries now show inline `default:` / `required` annotations next to the
usage label, with the brief on a separate indented line. The `default` modifier
surfaces its value in help (suppressed for `nothing` and `false` flags).

### `choices:` annotation
`choice(...)` value parsers produce `choices: a, b, c` in help, composed with
`default:` and `required` (e.g. `default: safe  choices: fast, safe`). The new
generic `usage_annotations(::AbstractValueParser)` hook lets any value parser
contribute its own annotations.

### Structured per-parser errors
Errors are now concrete structs (`<: AbstractParseError`) with typed codes
instead of a flat domain/code enum. Each parser family owns its error type,
making rendered messages more precise and extension easier.

### New display / tree printer
Parsers render as a tree in the REPL (`show(MIME"text/plain"(), parser)`).
Extend with `show_children` and `printnode` for custom parsers.

### Type parameter additions
`AbstractParser` now carries five type parameters `{T, E, S, P, R}`, surfacing
the error union (`E`) and priority (`R`) at the type level. This improves
inference and trimming without changing the public API.

## Bug Fixes

- Empty `argv` with optional fields in `record` no longer fails incorrectly
  (issue #9).
- Unrecognized tokens in `partial` parsing are now handled correctly.
- The entrypoint loop returns the correct error when the parser makes no
  progress.

## Breaking Changes

### `@parser` macro now uses `struct` syntax
The macro is applied to a `struct` definition instead of wrapping a `begin ...
end` block. Parser-level description and footer use `@description` / `@footer`
markers inside the body rather than positional string arguments.

**Before:**
```julia
parser = @parser "Server configuration" Config begin
    "Host"
    host = option("--host", str("HOST"))
    "Port"
    port = option("--port", integer("PORT"))
end "Server configuration parser"
```

**After:**
```julia
@parser struct Config
    @description "Server configuration"
    "Host"
    host = option("--host", str("HOST"))
    "Port"
    port = option("--port", integer("PORT"))
    @footer "Server configuration parser"
end

# The parser is retrieved via `lift`:
parser = lift(Config)
# Or used directly with the entrypoints:
optparse(Config, args)
```

### `str()` rejects empty strings by default
`str()` now rejects empty-string input unless `allow_empty=true` is passed.

### Other breaking changes

- `default_metavar` removed — metavar is now always set via constructors.
- Parser type parameters reordered: any code matching on raw type params needs
  updating (public API functions like `valuetype`, `priority` are unchanged).
- Error rendering: custom parsers must define `render_error(io::IO, err::MyError)`
  on a concrete `<: AbstractParseError` struct instead of the old domain/code
  pattern.
