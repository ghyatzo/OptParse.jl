
#=---
Usage subsystem overview

This code builds and renders a syntax-level usage AST. The intended shape is:

- `UsageFlag` / `UsageOption` / `UsageArgument`
  Leaf syntax nodes.
- `UsageCommand`
  Prints the command token, then renders the child usage under that prefix.
- `UsageObject`
  Named product parser usage.
- `UsageTuple`
  Positional product parser usage.
- `UsageAlternative`
  Branch choice usage.
- `UsageOptional` / `UsageRepeat`
  Syntax wrappers for optional/repeated subtrees.
- `UsageHidden`
  Parser is semantically relevant but omitted from usage output.

Current rendering goals:

- compact mode is the default error-oriented synopsis
- expanded mode keeps the same syntax tree but allows more structure
- compact `UsageObject` collapses optional option-like children into `[OPTIONS]`
- `UsageAlternative`
  - if every visible branch is a command: render `<COMMAND> [ARGS...]`
  - if there are at most 2 visible branches: render inline as `(a | b)`
  - otherwise: render stacked, bounded to two concrete lines plus `...`
- `UsageTuple` and expanded `UsageObject` render as visible children in order
- optional nodes render as `[child]`
- repetition renders as `child...`, `[child]...`, or explicit repeated items

Examples of the intended compact output:

- object of optional options plus one argument:
  `[OPTIONS] <FILE>`
- tuple / sequence:
  `<SRC> <DST>`
- two-way alternative:
  `(<FILE> | <DIR>)`
- command alternatives:
  `<COMMAND> [ARGS...]`

The implementation is split across:

- `nodes.jl`   : usage AST node definitions
- `traits.jl`  : tree facts and layout decisions
- `render.jl`  : rendering logic

This file is the entrypoint so readers can start here before diving into the
lower-level helpers.
=#

include("nodes.jl")
include("traits.jl")
include("render.jl")
