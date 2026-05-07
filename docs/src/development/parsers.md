# Parser Semantics

## Parser Families

OptParse currently has three parser-family categories.

### Primitive parsers

Primitive parsers are the leaves of the structural parser tree.

Current primitives:

- `gate`
- `flag`
- `option`
- `arg`
- `command`
- `@constant`

These generally:

- inspect the next token(s)
- update a small family-specific state
- do not recurse into several child parsers, except `command`

### Constructors

Constructors combine several child parsers into a larger parser.

Current constructors:

- `object`
- `or`
- `sequence`
- `concat`
- `combine`

These are where most of the parser-control semantics live.

### Modifiers

Modifiers wrap another parser and adjust matching or completion behavior.

Current modifiers:

- `default`
- `optional`
- `repeated`

## Priority

Every parser carries a compile-time priority parameter `p`.

This is not user-facing API, but it is an important implementation detail because
several constructors rely on it to decide which child parser gets first shot at
the current input.

You can inspect it via:

```julia
priority(parser_or_type)
```

### What priority is for

Priority exists to make greedy constructor behavior deterministic and practical.

Examples:

- `object` sorts its children by descending priority before matching
- `sequence` uses priority when deciding which of the remaining slots to try first
- the constructed parser often uses `max(child priorities...)` as its own priority

This lets the parser tree prefer more structured or less ambiguous matches before
broader fallback parsers.

### What priority is not

Priority is not:

- a user-facing semantic guarantee
- part of the parsed result
- a substitute for explicit `or(...)` branch order

For `or(...)`, source order still matters. Priority is primarily for constructor
internals like `object` and `sequence`.

### Current priority breakdown

The current built-in parser families use these priorities:

| Parser family | Priority | Notes |
| --- | ---: | --- |
| `command` | `15` | Highest built-in primitive priority; command tokens should win early. |
| `option` | `10` | Explicit option syntax with attached value. |
| `gate` | `9` | Required presence flag. |
| `arg` | `5` | Positional parser; lower than explicit option, flag, or command syntax. |
| `@constant` | `0` | Non-consuming marker parser. |

Wrappers and constructors currently behave as follows:

| Parser family | Priority rule | Notes |
| --- | --- | --- |
| `flag` | inherits `gate` | Public `flag(...)` is implemented as `default(gate(...), false)`. |
| `default` | inherits child priority | `ModWithDefault` uses `priority(P)`. |
| `optional` | inherits child priority | `optional` is `default(p, nothing)`. |
| `repeated` | inherits child priority | `ModMultiple` uses `priority(P)`. |
| `object` | `maximum(child priorities)` | Children are also sorted by priority before matching. |
| `or` | `maximum(child priorities)` | Branch order still defines semantics; the stored priority mainly affects parent constructors. |
| `sequence` | `maximum(child priorities)` | Remaining unmatched slots are tried in priority order. |
| `combine` / `concat` | derived from the resulting constructor | They lower into `object` / `sequence` constructor values rather than introducing a separate priority scale. |

So the effective current ordering is roughly:

```text
command > option > gate/flag > arg > @constant
```

### Guidance for new parser families

When adding a new parser family:

- choose a priority intentionally
- document the choice in code if it is not obvious
- remember that too-low priority can make the parser starve behind broader siblings
- remember that too-high priority can make it greedily steal input from neighbors

As a rough mental model:

- primitives that match explicit option, flag, or command syntax usually have higher priority
- broader positional or fallback-like parsers are usually lower priority

## Semantics Of The Main Constructors

### `object`

Implementation: `src/parsers/constructors/object.jl`

`object` is an unordered greedy scope:

- it sorts children by parser priority for matching
- it keeps trying fields until no further progress can be made
- field order in the result follows the original named-tuple structure, but matching order is driven by priority

Important implications:

- `object` is not a branch selector
- matching one field does not exclude siblings
- this is why `object` is a poor fit for “selected path” semantics in future usage or help work

### `or`

Implementation: `src/parsers/constructors/or.jl`

`or` is the “first semantic branch wins” combinator.

Important behavior:

- branches are tried in the order provided
- control-only successes may mutate the running context without selecting a branch
- once a semantic branch has been selected, later parse steps stay inside that branch

Unlike `object` and `sequence`, `or` is defined primarily by source order, not by priority.

### `sequence`

Implementation: `src/parsers/constructors/tuple.jl`

`sequence` enforces ordered fulfillment of parser slots:

- each slot can only be satisfied once
- matching order is still priority-driven among the remaining slots
- a control-only success must not satisfy a slot
- if no remaining slot can match, parsing fails

This is why the implementation has two passes inside its loop:

- first try consuming matches
- then try non-consuming matches such as optional/default-like cases

### `command`

Implementation: `src/parsers/primitives/command.jl`

`command` is a two-stage primitive:

- before command selection, it expects the command token itself
- after selection, it delegates to the inner parser and stores inner state

Its state is `Option{Option{PState}}`, which distinguishes:

- command never matched
- command matched but inner parser has not started
- command matched and inner parser has started

### `repeated`

Implementation: `src/parsers/modifiers/repeated.jl`

`repeated` stores one child-state entry per matched repetition.

On each parse step it:

1. tries to continue the active repetition
2. if that does not produce a semantic match, tries to start a new repetition

Control-only successes must:

- propagate context
- not create or satisfy a repetition

This is another family where `counts_as_match` matters a lot.

