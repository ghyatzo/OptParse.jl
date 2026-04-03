# Development

Contributor-oriented development notes for OptParse.

The detailed internal guide lives in:

- [`docs/src/development/index.md`](docs/src/development/index.md)

That page is the canonical place for:

- parser architecture
- `Context` and parse result flow
- constructor semantics
- error propagation
- trimming / JET / inference notes
- adding parser families or value parsers


## Add A Value Parser

When adding a new value parser:

1. Add the concrete implementation under `src/parsers/valueparsers/`.
2. Add it to the wrapped `ValueParser` union in `src/parsers/valueparsers/valueparsers.jl`.
3. Add the public constructor(s) and docstring in `src/parsers/valueparsers/valueparsers.jl`.
4. Prefer the positional `metavar` API in examples when it makes sense.
5. Add pretty-printing support if needed.
6. Add unit tests, including `@test_opt`.
7. Add the constructor to `docs/src/reference.md`.

## Add A Parser Family

When adding a new parser family:

1. Decide whether it belongs in `primitives/`, `constructors/`, or `modifiers/`.
2. Define a concrete parser-family-specific state alias first.
3. Keep `parse` and `complete` signatures tight to the real state invariant.
4. Add family-specific error codes and an error renderer.
5. Add the family to the wrapped `Parser` union in `src/parsers/parser.jl`.
6. Add the public constructor and docstring in `src/parsers/parser.jl`.
7. Add `show_compact` / `show_pretty` support in `src/display/parser_show.jl`.
8. Add tests, including `@test_opt`.
9. Add the public constructor to `docs/src/reference.md` if it is exported.
