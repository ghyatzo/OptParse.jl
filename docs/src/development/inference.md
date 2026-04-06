# Inference And Trimming

OptParse is built with trimming in mind, so inference quality is not an optional
polish step.

## What To Test

Current tests generally use:

- ordinary behavior tests
- `@test_opt` for inference-sensitive paths
- trimming integration tests under `test/trim/`

When adding a parser family, add:

- direct primitive or family tests
- at least one `@test_opt` on the constructor itself
- at least one `@test_opt` through `optparse(...)`

## Common Inference Traps

1. Loose `parse` / `complete` signatures
2. Returning `Context` without preserving the state type parameter
3. Hidden type changes inside helper functions
4. Broadly typed higher-order helpers
5. Accidental materialization into abstract containers

## JET-Specific Lesson

A runtime path may be perfectly fine while JET still reports a dispatch problem if
wrapped-union branches are not trimmed by method signatures.

When that happens, check:

- whether the parser family method is too broadly typed
- whether constructor invariants are being expressed in dispatch
- whether a helper erased the state parameter from `Context{S}`

Do not paper over this with assertions first. Tighten the family invariants first.

## Why Tight State Dispatch Matters

The public `Parser` wrapper is a `@wrapped` union over all parser families.
That means inference will consider many possible parser-family arms unless your
method signatures rule impossible ones out early.

This is why a family-specific method like:

```julia
function parse(p::ArgOption{T, OptionState{T}}, ctx::Context{OptionState{T}})::InnerParseResult{OptionState{T}} where {T}
```

is much better than:

```julia
function parse(p::ArgOption, ctx::Context)
```

The tight version:

- documents the actual invariant of the family
- trims impossible union arms sooner
- keeps JET focused on reachable execution paths
- usually improves trimming behavior as well

## Current Design Notes

Two internal rules are worth keeping in mind while working on inference-sensitive code:

1. parser families should only operate on their own state shape
2. `Context` should be updated through its helper API so the state parameter stays explicit

If inference starts to widen, look there first before adding local assertions.

