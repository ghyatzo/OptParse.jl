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

The current direction is cold-path state recovery:

```julia
recover_usage_context(parser, args)::Context
```

or a similar internal function.

The function should replay parsing over the same normalized argv and recover the
most useful parser state/context for usage or help generation. This is only for
errors and explicit help requests, not the normal successful parse path.

Normal parsing should stay lean:

1. Parse normally.
2. If parsing succeeds, do no help work.
3. If parsing fails, render the structured error.
4. Error rendering asks for usage/help context.
5. The cold path replays enough parser state to decide the relevant help scope.
6. Rendering combines the original `ParseError` with focused usage/help.

The recovery function should not be responsible for rendering. Its job is to
produce the state needed by a later focus step.

A likely split is:

```julia
recover_usage_context(parser, args)::Context
focused_usage(parser, ctx)::UsageNode
```

Later, when `Help` exists, the second function likely becomes:

```julia
focused_help(parser, ctx)::Help
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

## Help Object Plan

Usage should remain the syntax synopsis. Help should be represented by a richer
semantic object.

A possible shape:

```julia
struct Help
    usage::UsageNode
    brief::String
    description::String
    entries::Vector{HelpEntry}
    footer::String
end

@enum HelpEntryKind begin
    HELP_Option
    HELP_Argument
    HELP_Command
    HELP_Group
end

struct HelpEntry
    kind::HelpEntryKind
    names::Vector{String}
    metavar::String
    brief::String
    help::String
    usage::UsageNode
end
```

The exact fields can change. The important point is the layer boundary:

- parser families build or combine `Help`
- `UsageNode` remains only the synopsis AST
- `render_help(io, help::Help)` renders the help document
- `render_usage(io, usage::UsageNode)` remains independent

This lets each parser family combine help according to its behavior:

- `command` can prepend/select the command scope
- `or` can list command alternatives or branch alternatives
- `object` and `sequence` can collect child entries
- modifiers can wrap usage or annotate optional/repeated behavior
- hidden parsers can suppress entries without disappearing from parser semantics

This avoids overspecializing usage rendering to solve help problems.

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
An overlay parser may update one or more ScopedValues before delegating to its
wrapped parser in an auxiliary interpreter.
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

### Scoped Auxiliary State

The earlier manually threaded `env` idea is serviceable, but `ScopedValues`
match overlay semantics more closely.

Each auxiliary subsystem can own its own scoped state:

```julia
const HELP_INFO = ScopedValue(HelpInfo())
const SECTION_INFO = ScopedValue(SectionInfo())
```

Overlay nodes then update only the scoped state they care about and delegate:

```julia
focused_helpdoc(p::HelpOverlay, ctx, prefix) =
    with(HELP_INFO => merge_helpinfo(HELP_INFO[], p.info)) do
        focused_helpdoc(p.parser, ctx, prefix)
    end

focused_helpdoc(p::SectionOverlay, ctx, prefix) =
    with(SECTION_INFO => merge_sectioninfo(SECTION_INFO[], p.section)) do
        focused_helpdoc(p.parser, ctx, prefix)
    end
```

This has a few desirable properties:

- overlay composition stays orthogonal
- adding a new overlay does not force new method parameters through every
  traversal function
- each subsystem sees only the scoped state it cares about
- unrelated overlays do not couple independent auxiliary interpreters

For example, help traversal may care about `HELP_INFO` and `SECTION_INFO`, while
a future shell-completion interpreter may care about a different
`SHELL_COMPLETION_INFO` scoped value and ignore the help-related ones entirely.

### Parser-Owned Extraction Under Scoped State

Scoped values should not make overlays responsible for building help entries.
The underlying parser family still owns parser-specific extraction:

```julia
helpentry(p::ArgOption) =
    HelpEntry(
        usage = usage(p),
        info = HELP_INFO[],
        section = SECTION_INFO[],
        kind = HELP_Option,
    )
```

This keeps the syntax-specific knowledge with the parser family. An option knows
how to expose its names and metavar. A command knows how to expose its command
name and child scope. An object knows how to collect child entries. Overlays only
change the scoped interpretation state those parsers are interpreted under.

### HelpInfo, Sections, And Propagation

`HelpInfo` should be node-local information:

```julia
HelpInfo(
    hidden = false,
    brief = "...",
    description = "...",
    footer = "...",
)
```

It describes the parser node directly wrapped by `help(...)`. It should not
blindly propagate to every child.

For example:

```julia
object((...)) |> help("Configuration")
```

describes the object help scope, not every option inside the object.

Sections are different. A section is intended to group entries below it, so it
should propagate through constructor children:

```julia
object((;
    port = option("-p", "--port", integer("PORT")),
    tls = flag("--tls"),
)) |> section("Network")
```

should place both child entries under a `Network` section.

This suggests two different propagation modes for scoped auxiliary state:

```julia
HELP_INFO[]      # node-local
SECTION_INFO[]   # inherited / grouping
```

The likely rules are:

- `HelpInfo` is node-local and is reset when constructors descend into children
- `SectionInfo` is inherited and groups child entries until overridden
- overlays update only the scoped values they own and then delegate
- parser families produce `HelpDoc` / `HelpEntry` values under the currently
  visible scoped state

In practice, that means constructors such as `object(...)` will likely need
small scoped helper utilities so they can preserve inherited section state while
clearing node-local help state before descending into each child.

### Focused HelpDoc

The current `focused_usage` direction probably wants to generalize to a focused
help-document builder:

```julia
focused_helpdoc(parser, ctx)::HelpDoc
```

Error usage, `--help`, and help subcommands can all use the same focused
document and render different projections of it:

- error rendering may print only compact usage from the focused `HelpDoc`
- ordinary help may render usage, description, entries, sections, and footer
- future detailed help may render more entry-specific information

This avoids creating a separate focus mechanism for errors and for explicit help
requests.

### Future Auxiliary Environments

The same overlay idea can be reused for other cold-path interpreters:

- `HELP_INFO` / `SECTION_INFO` for help documents and usage focus
- `SHELL_COMPLETION_INFO` for shell completion candidates
- `SUGGESTION_INFO` for unknown-command or unknown-option suggestions
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

Scoped values should stay limited to these cold-path auxiliary interpreters.
They should not leak into the primary `parse` / `complete` runtime.

### Current Fallback Transport

`Base.ScopedValues` turned out not to be compatible with `--trim=safe` for the
actual rebinding path (`with(...)`), even though plain reads appear to trim.

That means the current practical fallback is a manual, interpreter-local version
of dynamic scope:

```julia
mutable struct HelpRuntime
    info::HelpInfo
    section::SectionInfo
end
```

A fresh runtime object is created for one top-level auxiliary traversal:

```julia
rt = HelpRuntime(HelpInfo(), SectionInfo())
focused_helpdoc(parser, ctx, rt)
```

Overlay nodes then update and restore runtime fields with explicit stack
discipline:

```julia
function with_helpinfo(rt::HelpRuntime, info::HelpInfo, f)
    old = rt.info
    rt.info = merge_helpinfo(old, info)
    try
        return f()
    finally
        rt.info = old
    end
end
```

The same pattern applies to section state and any future auxiliary interpreter
state.

The intended invariants are:

- runtime objects are created fresh per top-level auxiliary traversal
- they are never stored globally
- they are never shared across unrelated traversals
- they are only used for cold-path auxiliary interpreters
- `parse` / `complete` never depend on them

This preserves most of the benefits of the `ScopedValues` model:

- overlays still behave like dynamically scoped interpreters
- parser families still own syntax-specific extraction
- different auxiliary subsystems can have different runtime objects
- migration to real `ScopedValues` should be mechanically straightforward later

The migration story is intentionally simple: if `ScopedValues` become trim-safe
in the future, the helper layer around `HelpRuntime` / `SectionRuntime` can be
swapped for real scoped values with minimal changes to the higher-level overlay
interpreter structure.

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

- exact signature and name of the recovery function
- how much of parse should be replayed for help requests
- whether recovery should stop at first failure or return the furthest useful
  state
- how complete-phase errors should choose a focus scope
- exact `HelpDoc`, `HelpEntry`, and `HelpEnv` field layout
- whether `ModHelp` should eventually move to an `overlays/` parser family and
  be renamed to something like `HelpOverlay`
- exact section propagation rules through `object`, `sequence`, `or`,
  `command`, and behavioral modifiers

## Practical Next Steps

The next implementation steps are:

1. Keep `usage(parser)::UsageNode` generation type-stable for all parser
   families.
2. Add focused tests that build usage from real parsers, not only hand-written
   `UsageNode`s.
3. Add a cold-path recovery function that replays parser state from argv.
4. Implement root/focused usage selection from recovered state.
5. Formalize `HelpInfo` as node-local overlay information.
6. Introduce a minimal `HelpEnv` / `HelpDoc` only after usage focus is working.
7. Keep rendering as the final pure step over `UsageNode` or `HelpDoc`.

## Summary

The intended architecture is:

- parser tree is the source of truth
- `UsageNode` is a concrete syntax AST
- `usage(parser)` generates usage on demand
- root usage can be stored in `Context`
- normal parsing does not maintain breadcrumbs or mutable usage focus
- focused usage/help comes from cold-path state recovery
- overlays are transparent parser nodes interpreted through auxiliary
  environments
- help should become a semantic `HelpDoc` object, not an overloaded usage
  renderer
