# Development

This section documents the internal structure of OptParse and the conventions
that matter when extending it.

It is intended for:

- contributors adding a new parser family or value parser
- maintainers changing parser internals while preserving trimming and inference
- curious users who want to understand how the parser tree is executed

For the user-facing API, see:

- [Overview](../index.md)
- [Examples](../examples.md)
- [API Docstrings](../reference.md)

## Guide Structure

- [Runtime Model](runtime.md)
  - `AbstractParser{T,S,p,P}`
  - parse vs complete
  - parser state
  - `Context`, `Consumed`, and parse results
  - structured errors
- [Parser Semantics](parsers.md)
  - primitive / constructor / modifier categories
  - parser priority
  - semantics of `object`, `or`, `sequence`, `command`, and `multiple`
- [Extending OptParse](extending.md)
  - how to add a value parser
  - how to add a parser family
  - public API / docs / test checklist
- [Inference And Trimming](inference.md)
  - concrete parser trees
  - tight state signatures
  - common inference traps
  - JET / trimming notes

## Short Contributor Summary

If you only need the shortest version:

- start from a parser-family-specific state alias
- keep `parse` and `complete` signatures tight
- interact with `Context` through the helper API
- add family-specific errors and a renderer
- keep child parser fields concrete and parametric
- keep public names, display output, docs, and tests in sync
