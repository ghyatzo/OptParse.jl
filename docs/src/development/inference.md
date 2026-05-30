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
impossible parser-family instantiations are not ruled out by method signatures.

When that happens, check:

- whether the parser family method is too broadly typed
- whether constructor invariants are being expressed in dispatch
- whether a helper erased the state parameter from `Context{S}`
- whether the error type `E` is properly constrained

Do not paper over this with assertions first. Tighten the family invariants first.

## Why Tight State Dispatch Matters

Even with a concrete parser tree, inference will consider many possible
parser-family instantiations unless your method signatures rule impossible ones
out early.

This is why a family-specific method like:

```julia
function parse(p::ArgOption{T, E, OptionState{T, E}}, ctx::Context{OptionState{T, E}})::InnerParseResult{OptionState{T, E}, E} where {T, E}
```

is much better than:

```julia
function parse(p::ArgOption, ctx::Context)
```

The tight version:

- documents the actual invariant of the family
- trims impossible instantiations sooner
- keeps JET focused on reachable execution paths
- usually improves trimming behavior as well

## Wrapper Child-State Invariants

For wrapper parsers, also constrain the child parser type parameter.

The common trap is writing a wrapper method that constrains the wrapper state but
leaves the child parser type unconstrained:

```julia
function parse(p::ModHelp{T, E, S, P, _R}, ctx::Context{S}) where {T, E, S, P, _R}
```

Runtime construction may guarantee that `P` is a parser whose state is `S`, but
the method signature does not say that. JET can then explore impossible
instantiations of `P`, such as a child parser whose state does not match
`Context{S}`.

Prefer:

```julia
function parse(
    p::ModHelp{T, E, S, P, _R},
    ctx::Context{S},
)::InnerParseResult{S, E} where {T, E, S, _R, P <: AbstractParser{<:Any, <:Any, S}}
```

For wrappers with nested child state, bind `P` to the inner state:

```julia
function complete(
    p::ModWithDefault{T, E, WithDefaultState{S}, P, _R},
    state::WithDefaultState{S},
)::ParseResult{T, E} where {T, E, S, _R, P <: AbstractParser{<:Any, <:Any, S}}
```

This invariant was exposed by the help information modifier wrapping `default`.
The parser values were valid, but the unconstrained method left inference free
to consider impossible child-state combinations.

## Current Design Notes

Two internal rules are worth keeping in mind while working on inference-sensitive code:

1. parser families should only operate on their own state shape
2. `Context` should be updated through its helper API so the state parameter stays explicit
3. wrapper methods should constrain child parser type parameters to the child state they delegate to

If inference starts to widen, look there first before adding local assertions.
