# Usage / Help Design Notes

This file collects the current direction for OptParse usage and help generation.

It is not a frozen spec. It exists so the current design constraints and next
steps can be picked up again later without reconstructing the whole discussion.

## Scope

There are three related but distinct layers:

- **usage**
  - a compact synopsis of accepted command-line syntax
  - represented by `UsageNode`
  - rendered by `render_usage`
- **help**
  - a semantic help document for one parser scope
  - should contain usage plus descriptions, sections, entries, footers, and
    examples
- **help policy**
  - decides when help is requested and which scope it should describe
  - examples: parse error, `--help`, help subcommand

The current implementation work is focused on usage first, but the design
should leave room for help to become a richer object instead of overloading the
usage renderer.

## Current Direction

The parser tree is the source of truth.

Usage should be generated from parsers on demand:

```julia
usage(parser)::UsageNode
```

Each parser family owns the lowering from its parser structure to the usage AST:

- `gate(...)` / `flag(...)` -> `UsageFlag`
- `option(...)` -> `UsageOption`
- `arg(...)` -> `UsageArgument`
- `command(...)` -> `UsageCommand`
- `object(...)` -> `UsageObject`
- `sequence(...)` -> `UsageTuple`
- `or(...)` -> `UsageAlternative`
- `optional(...)` / `default(...)` -> `UsageOptional`
- `multiple(...)` -> `UsageRepeat`
- `@constant(...)` -> `UsageHidden`

`UsageHidden` exists for parser nodes that are semantically important but should
not appear in usage output.

## Usage AST

The current usage AST is a single concrete node type:

```julia
struct UsageNode
    kind::UsageKind
    names::Vector{String}
    metavar::String
    children::Vector{UsageNode}
    min::Int
    max::Int
end
```

This is intentionally a syntax AST, not a full help document model.

It should not grow fields for:

- long descriptions
- examples
- footer text
- section headings
- trigger policy

Those belong in a later `Help` layer.

The important compiler constraint is to keep the AST concrete. The backing child
storage can be a concrete `Vector{UsageNode}` because the node type itself is not
abstract and rendering/generation remain type-stable. Avoid `Vector{Abstract...}`
or runtime-dispatched recursive node hierarchies.

## Usage Generation

Usage generation should be cold-path and on demand.

Normal parsing should not eagerly maintain or mutate a parallel usage tree. A
parser can generate its root usage when needed, and `tryargparse` may store that
root usage in `Context` so error/help code has access to the original synopsis.

Constructor usage generation should preserve declaration order, not parse
priority order.

This matters especially for `object(...)` and `sequence(...)`:

- parsing may sort children by priority internally
- usage should reflect the order the user wrote
- display order is user-facing API
- parse order is implementation detail

When constructor usage generation needs to collect child usage nodes, avoid
splatting. Prefer index-based generated helpers or other concrete paths that
remain friendly to trimming and JET.

## Rendering

`render_usage` should stay a pure renderer over `UsageNode`.

It should not need to know:

- parser internals
- parser state
- parse errors
- help triggers
- how focus was recovered

The current renderer distinguishes compact and expanded usage styles.

Compact usage is primarily intended for terse summaries and errors:

- `[OPTIONS] <FILE>`
- `<SRC> <DST>`
- `(<FILE> | <DIR>)`
- `<COMMAND> [ARGS...]`

Expanded usage can show more syntax detail, but it is still usage, not full
help.

The renderer can own layout policy such as:

- collapsing optional option-like children under `object(...)` into `[OPTIONS]`
- stacking large heterogeneous alternatives
- collapsing command alternatives into `<COMMAND> [ARGS...]`

It should not become the place where descriptions, examples, grouping, or help
scope policy live.

## Focused Usage / Help

The earlier breadcrumb/cursor design became too complex and should not be the
main path.

The current direction is cold-path state recovery plus a second focused tree
walk:

```julia
recover_usage_context(parser, args)::Context
build_help_doc(parser, args)::HelpDoc
focused_helpdoc(parser, ctx, rt)::HelpDoc
```

`recover_usage_context` replays parsing over normalized argv and returns the
most useful recovered parser state/context for later help generation.

`build_help_doc` is the current top-level helper:

```julia
ctx = recover_usage_context(parser, argv)
focused_helpdoc(parser, ctx, root_overlay_context())
```

This is a cold path for explicit help and future error rendering, not part of
the normal successful parse path.

Normal parsing should stay lean:

1. Parse normally.
2. If parsing succeeds, do no help work.
3. If parsing fails, render the structured error.
4. Error/help policy asks for usage/help context.
5. The cold path replays enough parser state to decide the relevant help scope.
6. Rendering projects the resulting `HelpDoc` into a compact usage or a fuller
   help page.

The recovery function should not be responsible for rendering. Its job is to
produce the state needed by a later focus step.

The important split is:

```julia
recover_usage_context(parser, args)::Context
focused_helpdoc(parser, ctx, rt)::HelpDoc
```

## State-Based Focus

Focused usage/help should be derived from parser state.

Initial focus rules can be conservative:

- if no meaningful parser state was recovered, use root usage
- if a command has been selected, focus on that command scope
- if an `or` branch has been selected, focus on that branch scope
- if an aggregate parser such as `object(...)` or `sequence(...)` is active,
  keep the aggregate as the current scope unless a child represents a stronger
  boundary

`object(...)` is not a branch selector. It visits many children, possibly across
many iterations. That makes it a poor fit for persistent path semantics, but it
can still contribute to help by collecting child entries.

`sequence(...)` is closer to an aggregate than a branch selector too. Its output
shape is ordered, but matching may still be priority-driven internally.

`command(...)` and `or(...)` are the most important first focus boundaries.

## Help Document Model

Usage remains the syntax synopsis. Help is now represented by a separate
document object:

```julia
struct HelpEntry
    usage::UsageNode
    info::HelpInfo
end

struct HelpDoc
    prefix::Vector{String}
    usage::UsageNode
    info::HelpInfo
    entries::Vector{HelpEntry}
end
```

The exact renderer behavior is still provisional, but the layer boundary is now
clear:

- parser families build or combine `HelpDoc`
- `UsageNode` remains only the synopsis AST
- `render_helpdoc(io, doc::HelpDoc)` renders the help document
- `render_usage(io, usage::UsageNode)` remains independent

The current model is intentionally minimal:

- `HelpInfo` holds prose and visibility for one focused node or one entry
- `HelpEntry` is the parent-page representation of a child parser
- `HelpDoc` is the focused scope that will be rendered

This is enough to exercise real help rendering without overloading the usage
renderer.

## Focused Documents And Entries

One important split is now explicit:

```julia
focused_helpdoc(parser, ctx, rt)::HelpDoc
helpentries(parser, rt)::Vector{HelpEntry}
```

These answer different questions:

- `focused_helpdoc(...)`
  - what help scope are we currently in?
- `helpentries(...)`
  - how should this parser contribute entries to its parent's help page?

This avoids the earlier mistake of trying to derive parent-page entries by
building a full focused document and then flattening it again.

The current intended behavior is:

- leaf parsers such as `arg`, `option`, `gate`, and `command`
  - produce one `HelpEntry`
- structural constructors such as `object` and `sequence`
  - are entry-transparent and flatten child entries
- `or`
  - is currently kept flat as a practical first implementation, even though
    branch-aware help semantics will likely need refinement later
- wrappers such as `default` and `multiple`
  - may transform atomic child entries
  - should leave group-like child entries alone and express group semantics in
    focused usage instead

This flat-entry rule is deliberate. Nested parser structure should affect focus
and usage shape, but not leak directly as nested `Vector{Vector{HelpEntry}}`
into the renderer.

## Overlay Parsers And Auxiliary Environments

Help information, sections, visibility, suggestions, and shell-completion hints
look like a separate parser family.

They are not primitive parsers, constructors, or behavioral modifiers. They are
**overlays**: transparent parser nodes that attach information to a subtree by
changing subsystem-specific scoped interpretation state.

The core rule:

```text
Overlays are transparent to the primary parse/complete interpreter.
They are meaningful to auxiliary interpreters such as help, usage focus,
shell completion, suggestions, and diagnostics.
```

More concretely:

```text
An overlay parser may update subsystem-specific auxiliary interpretation state
before delegating to its wrapped parser in an auxiliary interpreter.
```

An overlay parser should preserve the wrapped parser's primary semantics:

- same result type `T`
- same state type `S`
- same priority `p`
- same initial state
- same parse behavior
- same complete behavior

For example, the current help modifier is conceptually an overlay:

```julia
flag("-v") |> help("Verbose output")
```

The flag still parses exactly like the original flag. The `help(...)` layer only
changes what the help/documentation interpreter sees.

This suggests a future taxonomy:

- primitive parsers match CLI syntax directly
- constructors combine parser results into larger result shapes
- behavioral modifiers change parse or complete behavior
- overlays modify auxiliary environments for secondary tree interpreters

### Current Overlay Transport

The current implementation does not use `Base.ScopedValues`.

Real rebinding with `with(...)` is not compatible with the trimming
requirements, so the help path currently uses an explicit overlay context
parameter:

```julia
struct OverlayContext
    info::HelpInfo
end

root_overlay_context() = OverlayContext(HelpInfo())
with_helpinfo(rt, info) = ...
descend_child(rt) = ...
```

That gives the current help walk a simple and trim-safe transport.

The important rule is still the same: overlays update auxiliary interpretation
state and delegate. Parser families still own syntax-specific extraction.

For example:

```julia
helpentries(p::ModHelp, rt) =
    ishidden(p.info) ? HelpEntry[] : helpentries(p.parser, with_helpinfo(rt, p.info))
```

### Propagation Semantics

`HelpInfo` is currently treated as node-local information. Constructors clear it
when they descend into children:

```julia
descend_child(rt) = OverlayContext(HelpInfo())
```

This matches the current intended semantics:

- `object((...)) |> help("Configuration")`
  - describes the object help scope
  - not every child entry inside the object
- child entries must pick up only the help information explicitly attached to
  those child nodes

If sections are added later, they will likely need inherited propagation, which
means `OverlayContext` will probably grow beyond `HelpInfo` and the propagation
helpers will become more semantic.

### Renderer Status

The help renderer is now a separate path:

```julia
render_usage(doc::HelpDoc)
render_helpdoc(doc::HelpDoc)
```

`render_usage(doc)` renders the focused usage line using `doc.prefix` and
`doc.usage`.

`render_helpdoc(doc)` renders a fuller help page using:

- `doc.info`
- the focused usage line
- `doc.entries`

The current formatting is intentionally rough. Entry layout will likely need
usage-kind-specific rendering later, but the architectural split is now in
place.

### Future Auxiliary Environments

The same overlay idea can be reused for other cold-path interpreters:

- help info / section state for help documents and usage focus
- shell-completion state for shell completion candidates
- suggestion state for unknown-command or unknown-option suggestions
- diagnostic scoped state for deprecation notes or richer error hints

The boundary should stay explicit:

- if a feature changes the parsed value or completion semantics, it is a
  behavioral modifier
- if a feature only changes a secondary interpretation of the parser tree, it is
  an overlay

For example, "read a missing default from an environment variable" probably
changes the final parsed value, so it is likely a behavioral modifier. But
"document that this option can be completed from an environment variable" is an
overlay.

These auxiliary environments should stay strictly out of the primary
`parse` / `complete` runtime.

## Help Triggers

Known help/usage entry points:

- parse error
- `--help` or equivalent help flag
- help subcommand

Other possible future entry points:

- shell completion metadata
- suggestions for unknown flags or commands
- richer diagnostics for ambiguous input

Those should be policy decisions above parser semantics. The parser tree should
provide enough structured information, but it should not hard-code one help
trigger model.

## Open Questions

The main unresolved questions are:

- how error rendering should request and display focused help
- how explicit `--help` and help-subcommand policy should be wired into
  `optparse`
- how much of parse should be replayed for help requests in the long term
- whether recovery should stop at first failure or return the furthest useful
  state
- exact long-term `HelpDoc` / `HelpEntry` field layout
- whether `ModHelp` should eventually move to an `overlays/` parser family and
  be renamed to something like `HelpOverlay`
- exact section propagation rules through `object`, `sequence`, `or`,
  `command`, and behavioral modifiers
- whether entry atomicity / transparency should become an explicit parser-family
  distinction in the type system

## Practical Next Steps

The next implementation steps are:

1. Keep `usage(parser)::UsageNode` generation type-stable for all parser
   families.
2. Add focused tests that build `HelpDoc` from real parsers, not only
   hand-written `UsageNode`s.
3. Exercise `build_help_doc(parser, argv)` over realistic command/object/or
   trees.
4. Wire `HelpDoc` into actual help triggers and error rendering.
5. Refine `render_helpdoc` once the current output has been evaluated on larger
   examples.
6. Decide whether entry atomicity / transparency should be encoded with
   abstract parser families or traits.

## Summary

The intended architecture is:

- parser tree is the source of truth
- `UsageNode` is a concrete syntax AST
- `usage(parser)` generates usage on demand
- root usage can be stored in `Context`
- normal parsing does not maintain breadcrumbs or mutable usage focus
- focused help comes from cold-path state recovery plus `focused_helpdoc`
- `HelpDoc` is now the semantic help object for one focused parser scope
- `helpentries` is a separate parent-page extraction path
- overlays are transparent parser nodes interpreted through auxiliary
  overlay context
- help rendering is a separate projection over `HelpDoc`, not an overloaded
  usage renderer
