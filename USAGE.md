# Usage / Help Design Notes

This file collects the current direction for OptParse usage and help generation.

It is not meant to be a frozen spec yet. The goal is to preserve the design
decisions already made, the constraints that led to them, and the current rough
plan for the next steps.

## Scope

There are three related but distinct things:

- **usage**
  - a synopsis of how to invoke the parser
  - primarily a syntax summary
- **quick help**
  - a branch-specific help page, typically shown by `--help`
  - usage plus short sections such as options / arguments / commands
- **full help**
  - a richer report, closer to a man page
  - usage plus longer descriptions, examples, footer, etc.

The current implementation work is focused on **usage** first.

The intended split is:

- build one usage model
- reuse it in different render modes
- layer quick help and full help on top later

## General Principles

### 1. Usage should be derived from the parser tree

The parser tree is the source of truth.

Usage should not be hand-written separately, and parsing should not mutate a
second parallel usage tree at runtime.

Instead:

- each parser owns a usage subtree
- parent parsers build their usage subtree from their children
- rendering walks that static tree

### 2. Usage and help are not the same

The one-line or compact usage shown on errors should stay compact.

The larger help views should reuse the same synopsis renderer, but add their own
sections on top.

So the design should keep these concepts separate:

- usage rendering
- help rendering
- help triggers / dispatch policy

### 3. Context-sensitive usage must come from parser progress, not a second parser

If the parser fails deep inside a selected command / branch, usage should be
able to render the active branch path, not only the whole root parser.

That means the system needs some runtime notion of the currently selected path,
but not a second mutable usage tree.

## Current Usage AST Direction

The current implementation lives in:

- [src/usage/usage.jl](src/usage/usage.jl)
- [src/usage/nodes.jl](src/usage/nodes.jl)
- [src/usage/traits.jl](src/usage/traits.jl)
- [src/usage/render.jl](src/usage/render.jl)

The usage tree is intentionally represented as a **tuple-based concrete AST**,
not as `Vector{AbstractUsageNode}`.

This matters for inference and compilation on current Julia versions:

- abstract containers would introduce dynamic dispatch
- wrapped unions are awkward for recursive self-referential trees
- Julia 1.12 does not yet solve that cleanly

So the usage tree uses concrete parametric nodes with tuple children.

Current node families:

- `UsageFlag`
- `UsageOption`
- `UsageArgument`
- `UsageCommand`
- `UsageObject`
- `UsageTuple`
- `UsageAlternative`
- `UsageOptional`
- `UsageRepeat`
- `UsageHidden`

This is a **syntax AST**, not a full help document model.

It deliberately does not currently try to encode:

- help prose
- examples
- section headers
- trigger policy

Those belong in higher layers later.

## Lowering Model

The intended lowering is:

- leaf parser -> leaf usage node
- wrapper / constructor parser -> usage node built from child usage nodes

Rough mapping:

- `flag(...)` -> `UsageFlag`
- `option(...)` -> `UsageOption`
- `arg(...)` -> `UsageArgument`
- `command(...)` -> `UsageCommand`
- `object(...)` -> `UsageObject`
- `sequence(...)` -> `UsageTuple`
- `or(...)` -> `UsageAlternative`
- `optional(...)` / `default(...)` -> `UsageOptional` in syntax terms
- `multiple(...)` -> `UsageRepeat`
- `@constant(...)` -> `UsageHidden`

`UsageHidden` exists because some parsers are semantically important but should
not appear in usage output.

## Rendering Modes

The current renderer already distinguishes between:

- compact usage
- expanded usage

These are usage layout modes, not full help modes.

### Compact Usage

Compact usage is primarily intended for errors and terse summaries.

Desired properties:

- minimal noise
- usually one logical line
- still allowed to spill to a few lines for large alternatives

Compact mode applies presentation policies such as:

- collapse optional option-like children under `object(...)` into `[OPTIONS]`
- keep positional arguments explicit
- keep required options explicit

Typical compact shapes should look like:

- `[OPTIONS] <FILE>`
- `<SRC> <DST>`
- `(<FILE> | <DIR>)`
- `<COMMAND> [ARGS...]`

### Expanded Usage

Expanded usage is still only usage, but is allowed to show more structure.

The current implementation mostly keeps the same syntax tree but uses a more
explicit layout where needed.

Typical expanded shapes should still preserve the same core syntax, but may
spell out object children instead of collapsing them behind `[OPTIONS]`.

## Alternative Rendering Policy

`UsageAlternative` is the main place where compact policy matters.

Current policy:

- if all visible branches are commands, collapse to:
  - `<COMMAND> [ARGS...]`
- else, if there are at most 2 visible branches:
  - render inline as `(a | b)`
- else:
  - render stacked
  - show at most 2 concrete lines
  - then show `...`

This keeps compact usage readable when many alternatives exist.

The intent is:

- compact mode should not dump huge `a | b | c | d | ...` expressions inline
- full branch listings belong in help, not in terse error usage

The same alternative node should own the layout choice in both compact and
expanded usage, and then recurse into each branch using the incoming style.

## Object / Tuple Rendering

`UsageObject` and `UsageTuple` are structurally similar in the current renderer.

The important visible distinction is the result shape they imply:

- `UsageObject` corresponds to the named aggregation parser
- `UsageTuple` corresponds to the tuple aggregation parser

Compact object rendering has an extra policy:

- collapse optional option-like children into a single `[OPTIONS]`

This is a presentation choice, not a syntax transformation of the underlying AST.

## Ordering

Usage should follow **declaration order**, not parse-priority order.

This matters especially for object-like parsers:

- parsing may sort children by priority internally
- usage should still reflect the order the user wrote

Display order is user-facing API.
Parse order is an implementation detail.

## Why Usage Is Not Threaded Through `Context`

One idea considered early was to thread a usage structure through `Context` and
update it as parsing proceeds.

That was rejected.

Reason:

- parsers such as `object`, `or`, and `multiple` probe speculatively
- speculative matching would then require usage rollback semantics too
- that duplicates problems the parser state model already solves

The current direction is:

- static usage tree on the parser
- small runtime path information in the parsing context
- root-based rendering using that path

## Breadcrumb Plan

To render usage for the active branch on failure, the system needs to know how
the parser descended through the tree.

The current direction is to store lightweight **breadcrumbs** in `Context`,
snapshot them on failure, and later use them while rendering usage from the root.

### Breadcrumb shape

The agreed shape is:

- lightweight enum/tag + integer index

The breadcrumb should identify a **structural choice**, not carry a whole usage
subtree.

### What should contribute breadcrumbs

Breadcrumbs are meant to represent meaningful narrowing decisions.

Good candidates:

- `or`
  - selected branch
- `command`
  - crossed command boundary / entered command child
- possibly `sequence`
  - if positional frontier turns out to be useful for focused usage

### What should *not* contribute persistent breadcrumbs

`object(...)` should not participate in the persistent breadcrumb path.

Reason:

- object matching is not really branch selection
- multiple object fields can match over time
- object field labels are parser-structure details, not usage-path concepts

So the current model is:

- `object` is breadcrumb-transparent
- it passes contexts through
- meaningful descendants keep whatever breadcrumb path they produce

## Focused Usage Rendering

Usage should ultimately render **from the root**, even when the error happened
in a nested parser.

Rendering from a detached child subtree is not enough, because the final output
still needs the root prefix, for example:

- `prog cmd subcmd ...`

not just:

- `subcmd ...`

So the intended long-term API shape is:

- render from the root usage tree
- optionally with a focused path / scope

This is why breadcrumb snapshots are needed.

## Help Plan

The longer-term help plan is still intentionally loose, but the high-level split
is:

- **usage**
  - shared synopsis engine
- **quick help**
  - branch-specific help, likely `--help` or `help` subcmd
- **full help**
  - richer report, more like a manual page

There was also discussion about letting users customize help trigger behavior,
for example mapping different flags / commands to different help modes.

That is a later policy layer and should not be baked into the usage AST itself.

## Open Design Constraints

### 1. The AST must stay compiler-friendly

The current tuple-based recursion is acceptable, but large trees may stress
compile time.

So future extensions should continue to avoid:

- abstract child containers
- runtime-dispatched recursive usage nodes

### 2. Help metadata should not distort usage syntax

Help-specific data such as:

- brief descriptions
- long descriptions
- examples
- footer / epilog

should likely live in metadata attached to parser families or commands, not in
the core syntax AST itself.

### 3. Compact output should stay compact

Error usage should remain terse.

Detailed listings belong in quick/full help, not in the compact synopsis.

## Practical Next Steps

The current high-value next steps are:

1. wire parser constructors to produce usage subtrees
2. keep declaration order available for usage rendering
3. finish breadcrumb plumbing through the parsers that represent real branch choices
4. add focused root-based usage rendering from breadcrumb snapshots
5. only then start building quick help on top

## Summary

The current intended architecture is:

- parser tree is the source of truth
- each parser owns a static usage subtree
- usage AST is tuple-based and concrete for inference reasons
- compact and expanded usage are rendering policies over the same tree
- breadcrumb snapshots provide runtime focus information for nested errors
- help is a later layer built on top of the usage engine

This is the direction to preserve unless later experience shows a clear need to
simplify or change it.
