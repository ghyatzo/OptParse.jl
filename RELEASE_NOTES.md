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

### Interface validation
`validate(parser)` checks at runtime that a parser correctly implements the
full `AbstractParser` interface. Useful during development of custom parsers.

## Improvements

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

## Breaking Changes

- `default_metavar` removed — metavar is now always set via constructors.
- Parser type parameters reordered: any code matching on raw type params needs
  updating (public API functions like `valuetype`, `priority` are unchanged).
- Error rendering: custom parsers must define `render_error(io::IO, err::MyError)`
  on a concrete `<: AbstractParseError` struct instead of the old domain/code
  pattern.
