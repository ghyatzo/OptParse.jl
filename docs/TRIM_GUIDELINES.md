# Trim-Safe Guidelines (Consolidated)

This document summarizes trim/trimmability lessons from prior sessions and fixes in this repository.

## Primary Rule

Keep call targets and result types concrete at trim verification boundaries.  
Most failures were not semantic bugs; they were unresolved calls caused by dynamic dispatch shape.

## Do

1. Prefer direct concrete calls over wrapper/helper indirection in trim-critical paths.
   - Example: call concrete parser internals directly once type is known, instead of bouncing through generic helpers.

2. Keep branch resolution statically enumerable.
   - For `or`-like combinators, generated/static branch blocks are safer than runtime-indexed dynamic calls.

3. Track branch identity explicitly in `or` state.
   - Do not infer branch identity from child state type alone (multiple branches may share the same state type).

4. Construct typed results directly at typed boundaries.
   - For `typedOk(::Type{T}, ...)` / `typedErr(::Type{T}, ...)`, construct `ParseResult{T}` concretely.
   - Avoid extra generic conversion layers in hot trim paths.

5. Keep state type parameters exact (especially `Context{S}` and `OrState`).
   - Be explicit about `S` to avoid invariance mismatches (`Context{Tuple{Val{0},...}}` vs `Context{Tuple{Union{Val...},...}}`).

6. Use compile-time type helpers in constructors.
   - Avoid runtime-ish container transforms in constructor type derivation (e.g. patterns that widen to `Any`).

7. Isolate and bisect trim failures with minimal variants.
   - Run parse-only.
   - Then parse + state extraction.
   - Then parse + complete.
   - This quickly localizes whether failure is parse, state flow, or complete.

8. Keep trimming tests variant-based and focused.
   - Use small trimmability fixtures that each stress one composition shape.

## Don’t

1. Don’t add helper indirection (`_foo_complete` wrappers) in unresolved-call regions.

2. Don’t rely on runtime index dispatch to choose branch parser completion.
   - `parsers[i]` + dynamic callee selection is a common verifier failure shape.

3. Don’t assume equal child state type implies same logical branch.

4. Don’t introduce generic result-constructor paths at typed boundaries if a concrete constructor is available.

5. Don’t “fix” by broadening types to `Any`/overly wide unions; this often silences inference locally but hurts trimming.

## Hotspots Seen Repeatedly

1. `ConstrOr.complete(...)` boundary.
2. `withDefault` composed with nested `or`.
3. Wrapper `Parser` orchestration (`parse`/`complete`) when concrete inner type is known but not used.
4. Constructor-time type-building logic that uses runtime-like transforms.

## Failure Signature -> Likely Cause -> First Fix

1. Signature: `Verifier error: unresolved call ... complete(::ConstrOr, ...)`
   - Likely cause: dynamic branch callee selection or non-concrete state path in `complete`.
   - First fix: make branch completion statically enumerated with explicit branch identity/state typing.

2. Signature: unresolved call involving wrapper dispatch (`Parser` + union/getfield chain)
   - Likely cause: extra wrapper/helper indirection obscuring concrete callee.
   - First fix: unwrap once to concrete inner parser type and call direct methods.

3. Signature: trims with 3 branches but fails with 4+
   - Likely cause: union-state or branch-selection scaling exposes dynamic dispatch path.
   - First fix: inspect branch identity/state encoding and generated branch enumeration.

4. Signature: unresolved call around typed result construction (`typedOk`/`typedErr`)
   - Likely cause: generic `ResultConstructor`/conversion path not closing under trim.
   - First fix: directly construct concrete `ParseResult{T}` at typed boundary.

5. Signature: method mismatch/inference confusion for `Context{S}`
   - Likely cause: parametric invariance mismatch between actual and expected `S`.
   - First fix: ensure context is created/threaded with exact state type parameter.

## Minimal Debug Workflow

1. Reproduce in test env (`TestEnv.activate(...)`) and run only trimmability target.
2. Capture first unresolved-call signature and owning source line.
3. Build smallest fixture that reproduces the same call shape.
4. Bisect path:
   - parse-only
   - parse + state extraction
   - parse + complete
5. Replace dynamic boundary with concrete equivalent.
6. Re-run target fixture, then full trimming suite, then full tests.

## Guardrails for New Parser/Combinator Work

1. When adding parser state unions, define explicit tagged branch state types.
2. Keep generated code branch-local and concrete; avoid generic collection transforms in generated return types.
3. At typed helper boundaries, prefer concrete construction over conversion chains.
4. Add a trimmability fixture before broad refactors so regressions are visible early.
