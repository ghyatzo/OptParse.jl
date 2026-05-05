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

Do not paper over this with assertions first. Tighten the family invariants first.

## Why Tight State Dispatch Matters

Even with a concrete parser tree, inference will consider many possible
parser-family instantiations unless your method signatures rule impossible ones
out early.

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
- trims impossible instantiations sooner
- keeps JET focused on reachable execution paths
- usually improves trimming behavior as well

## Wrapper Child-State Invariants

For wrapper parsers, also constrain the child parser type parameter.

The common trap is writing a wrapper method that constrains the wrapper state but
leaves the child parser type unconstrained:

```julia
function parse(p::ModHelp{T,S,_p,P}, ctx::Context{S}) where {T,S,_p,P}
```

Runtime construction may guarantee that `P` is a parser whose state is `S`, but
the method signature does not say that. JET can then explore impossible
instantiations of `P`, such as a child parser whose state does not match
`Context{S}`.

Prefer:

```julia
function parse(
    p::ModHelp{T,S,_p,P},
    ctx::Context{S},
)::InnerParseResult{S} where {T,S,_p,P <: AbstractParser{<:Any,S}}
```

For wrappers with nested child state, bind `P` to the inner state:

```julia
function complete(
    p::ModWithDefault{T,WithDefaultState{S},_p,P},
    state::WithDefaultState{S},
)::ParseResult{T} where {T,S,_p,P <: AbstractParser{<:Any,S}}
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
