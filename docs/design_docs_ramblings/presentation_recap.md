# OptParse: Bird's-Eye View Since The Last Release

This draft is meant as a presentation-oriented overview of what has changed
since the last release.

Rather than following the implementation history, it focuses on the larger
shifts in the library and the story the current API now tells.


## 1. The Public Surface Has Been Cleaned Up

One broad theme of this release is that the public API has become more
intentional.

Several names were revisited so the surface reads more like the underlying
parser model:

- `object(...)` became `record(...)`
- `multiple(...)` became `many(...)`, `many1(...)`, and `repeated(...)`
- `gate(...)` became `switch(...)`
- `resulttype(...)` became `valuetype(...)`
- public keyword arguments were normalized to `snake_case`

The point is not just cosmetic consistency.

These changes make the parser shape easier to read at the call site:

- `record` makes it obvious that the result is a named collection of fields
- `many` / `many1` / `repeated` make repetition semantics visible immediately
- `switch` is clearer than `gate` for required presence
- `valuetype` now reads more like a reflective helper than a primary modeling tool

This gives the library a cleaner split:

- use `record(...)` and `sequence(...)` for anonymous compositional structure
- use `valuetype(...)` when you want to inspect the output type of an anonymous parser
- use typed construction when the parsed value is part of your application model


## 2. Help Is Now A First-Class Application Story

Another major shift is the help model.

Previously, help generation existed mostly as a lower-level capability. That
capability still exists, but there is now a much clearer application-facing
story on top of it.

At the explicit layer, the help API is:

- `build_help_doc(parser, argv)`
- `generate_help(parser, argv; progname=...)`
- `print_help(io, parser, argv; progname=...)`

This keeps the parser tree as the single source of truth for:

- usage
- focused help scope
- help entries
- rendered help text

On top of that, there is now a dedicated runner:

- `runparse(parser, argv; ...)`

`runparse` is intentionally the policy layer. It leaves the core parser model
alone and adds CLI-oriented behavior:

- lexical help flags such as `--help`
- a positional help command through `helpcommand()`
- customizable behavior for bare invocation through `on_empty`

This is an important separation.

`tryoptparse` and `optparse` remain parser-centric entry points. `runparse` is
the convenience layer for actual command-line programs.

That means help is now available in two distinct but coherent ways:

- explicitly, when you want to generate or render help yourself
- automatically, when you want a top-level app runner that behaves like a CLI

Positional help is modeled as a normal parser through `helpcommand()`, which
completes to a `HelpRequest`. `runparse` can then inject that parser as a
hidden top-level branch and interpret the result by rendering help from the
original parser.

So the help story is now much stronger than before:

- help metadata lives inside the parser tree
- help rendering remains explicit and compositional
- automatic CLI help is handled by a dedicated top-level layer


## 3. Construction Now Has Two Clear Modes

The most important structural addition in this release is the new construction
story.

Before, anonymous parser results were often the end of the story. Now there is
a much cleaner progression from anonymous composition to typed application
models.

There are now two construction paths.

### Dynamic Construction: `construct`

`construct(T, parser)` is the flexible path.

It delegates to `StructUtils.make`, which means it can use the full
StructUtils machinery in normal Julia runtime:

- lifting existing user-defined types
- custom lifting behavior supplied through StructUtils
- richer reconstruction logic than a direct field-by-field constructor call
- construction of parametric structures when the dynamic environment can infer them

That last point is particularly nice: with the generic `construct` path, you
can construct parametric types directly when that information can be recovered
at runtime.

So `construct` is the "full power" mode:

- dynamic
- flexible
- user-extensible
- ideal for normal Julia environments

### Exact Construction: `construct_exact`

`construct_exact(T, parser)` is the strict path.

It exists for predictability and compiler-friendliness.

Instead of relying on generic reconstruction, it requires exact shape
agreement:

- for `record(...)` children, field names and order must match the struct exactly
- for `sequence(...)` children, positional arity and types must match exactly
- the target type must be concrete

This is the trim-friendly mode.

In dynamic Julia runtime, reflective reconstruction is often perfectly fine. In
trim-safe compilation, however, the most generic parts of reconstruction can be
hard or impossible for the verifier to resolve. `construct_exact` provides a
deliberately narrower path that is much easier to reason about under trimming.

So the split is now explicit:

- `construct` = dynamic, flexible, StructUtils-powered
- `construct_exact` = concrete, strict, trim-friendly

This is a much better design than trying to make a single construction API
serve both goals equally well.


## 4. A New Macro-First Typed Workflow

On top of `construct_exact`, the library now has a macro-first workflow:

- `@parser`

This is the ergonomic story for "define a type and its parser together".

The macro generates:

- hidden field parsers
- a struct whose field types are derived from those parsers via `valuetype(...)`
- a final `construct_exact(...)` parser that produces that struct

This is important because it removes a real source of drift: the user no
longer has to restate field types manually. The parser expressions themselves
determine the struct field types.

So the typed workflow now looks like this:

```julia
@parser "Clone a repository" CloneCmd begin
    "Silence progress output"
    quiet = flag("-q", "--quiet")

    branch = clone_branch

    "Repository to clone"
    repo = arg(str("REPO"))
end "Examples: ..."
```

That gives the library a very nice exact typed story:

- anonymous parsers when you want free composition
- `construct(...)` when you want dynamic lifting into existing types
- `construct_exact(...)` when you want strict, trim-friendly typed construction
- `@parser` when you want the strict typed path to be convenient and concise


## 5. Help Metadata Integrates Naturally With `@parser`

The typed macro workflow also ties into help cleanly.

Inside `@parser`:

- a string before a field becomes that field's brief help
- a leading parser-level help expression becomes the parser description
- a trailing parser-level help expression becomes the parser footer

Those outer help expressions do not have to be literal strings. They can also
be help modifiers, which means the macro composes naturally with the existing
help API rather than inventing a separate documentation mechanism.

There is also a useful style split here:

- short field strings work well for brief help
- larger field descriptions are still better kept in external helper parsers

That keeps the macro concise while still allowing richer documentation where it
actually helps readability.


## 6. The Overall Story Is Much Clearer Now

Stepping back, the release is not just a list of renames and additions. It
gives OptParse a much clearer high-level shape.

For public API design:

- the surface is more coherent
- naming better matches semantics
- migration is mechanical and documented

For help:

- explicit help generation remains available
- automatic CLI help now has a dedicated top-level story

For typed outputs:

- anonymous parser composition is still central
- dynamic lifting is available through full StructUtils integration
- trim-friendly exact construction now exists as a separate, deliberate path
- a macro makes that exact path pleasant to use

For deployment targets:

- dynamic Julia environments can use the full power of StructUtils, including
  custom lifting and parametric construction
- trim-oriented builds now have a narrower construction path designed for them

That is probably the biggest message of the release.

OptParse now has a better separation between:

- parser semantics
- application policy
- dynamic flexibility
- trim predictability

And because those concerns are separated more cleanly, the library can support
all of them without forcing them into a single overloaded abstraction.
