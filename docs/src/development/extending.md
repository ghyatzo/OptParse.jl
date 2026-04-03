# Extending OptParse

This page is the procedural part of the development guide: what to do when you
add a new value parser or parser family.

## Adding A New Value Parser

The shortest path is:

1. add a new file under `src/parsers/valueparsers/`
2. define the concrete value parser struct
3. define its call overload `(::YourValueParser)(input::String)::ParseResult{T}`
4. define `default_metavar(::YourValueParser)` if applicable
5. include it from `src/parsers/valueparsers/valueparsers.jl`
6. add it to the wrapped `ValueParser` union
7. add exported constructor functions and docstrings in `valueparsers.jl`
8. add compact display support in `src/display/parser_show.jl` if needed
9. add unit tests
10. add it to `docs/src/reference.md` if it is public

### Expected shape

Use existing value parser files as templates, especially:

- `string.jl`
- `integer.jl`
- `float.jl`

Typical pieces:

```julia
struct MyVal{T}
    metavar::String
    ...
end

default_metavar(::MyVal{T}) where {T} = "..."

function (p::MyVal{T})(input::String)::ParseResult{T} where {T}
    ...
end
```

### Constructor placement

Public constructor functions belong in `src/parsers/valueparsers/valueparsers.jl`,
not in the leaf file.

That file is the public API layer for value parsers and should contain:

- the public constructor names
- positional `metavar` overloads when appropriate
- docstrings

### Positional metavar style

The current preferred API is:

```julia
str("FILE")
integer("PORT")
flt("RATIO")
choice("MODE", values)
path("FILE")
```

The `metavar = ...` keyword still exists at the lower level, but docstrings and
examples should prefer the positional form.

### Value parser checklist

Before considering a value parser done, verify:

- parse returns `ParseResult{T}`
- errors are family-specific and rendered through `render_error`
- the constructor is in the wrapped `ValueParser` union
- the public constructor is exported if intended to be public
- `show` output is readable
- docstrings exist
- reference docs include the constructor
- unit tests cover success, failure, and `@test_opt`

## Adding A New Parser Family

The shortest path is:

1. decide whether it is a primitive, constructor, or modifier
2. add the concrete family file under the appropriate `src/parsers/...` subdirectory
3. define a family-specific state alias
4. define error codes and a renderer
5. define the concrete parser struct
6. implement `parse`
7. implement `complete`
8. include it from the family include file
9. add it to the wrapped `Parser` union in `src/parsers/parser.jl`
10. add the public constructor function and docstring in `src/parsers/parser.jl`
11. add `show_compact` / `show_pretty` support if needed
12. add tests
13. add docs, reference entries, and examples if public

### Start from a state alias

Always define a parser-family-specific state alias first.

Examples:

```julia
const GateState = ParseResult{Bool}
const OptionState{T} = ParseResult{T}
const CommandState{S} = Option{Option{S}}
const MultipleState{S} = Vector{S}
```

This usually clarifies the rest of the implementation immediately.

### Tight signatures

Use the family alias in method signatures:

```julia
function parse(p::ArgGate{Bool, GateState}, ctx::Context{GateState})::InnerParseResult{GateState}
```

Do not leave parser family methods broadly typed unless there is a very strong reason.

### Public constructor placement

Public constructor functions belong in `src/parsers/parser.jl`.

That file is the user-facing API layer for parser families:

- exported names
- docstrings
- curried convenience overloads where needed

### Parser-family checklist

Before considering a parser family done, verify:

- the state alias is explicit
- `parse` and `complete` signatures reflect the real invariant state type
- family-specific errors render correctly
- the family was added to the wrapped `Parser` union
- the public constructor exists and is exported if public
- `show` output is useful
- docs/examples/reference mention the new parser if public
- tests cover both behavior and inference

## Display And Docstring Conventions

### Public names should match displayed names

If the public constructor is `command(...)`, the parser pretty-printer should show
`command(...)`, not an older or internal alias.

Likewise:

- `flag(...)` should display as `flag(...)`
- `gate(...)` should display as `gate(...)`
- `sequence(...)` should display as `sequence(...)`

One subtle exception exists right now:

- `flag(...)` is implemented as `default(gate(...), false)`
- the pretty-printer special-cases this shape so public `flag(...)` still displays as `flag(...)`

### Reference docs must mention exported bindings explicitly

Documenter will complain if:

- an exported name has a docstring
- but the reference page does not include it in an `@docs` block

So when adding a public constructor, always update:

- `docs/src/reference.md`

