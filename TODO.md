# TODO

design and implementation notes for upcoming parser work.

## Tri-Valued Flag

- [ ] Add a parser for option pairs like `--[no-]tags`, producing `nothing`, `true`, or `false`.
- [ ] Use `nothing` when neither spelling is present.
- [ ] Use `true` for the positive spelling, for example `--tags`.
- [ ] Use `false` for the negative spelling, for example `--no-tags`.
- [ ] Decide whether the public name should be `tri_flag`, `toggle`, `option_flag`, or something else.
- [ ] Define duplicate/conflict behavior when both positive and negative spellings are present.
- [ ] Ensure generated usage/help can render both forms compactly.

Likely behavior:

```julia
tags = toggle("--tags")

optparse(tags, String[])        # nothing
optparse(tags, ["--tags"])      # true
optparse(tags, ["--no-tags"])   # false
```

## Additional Value Parsers

- [ ] Add date parsing.
- [ ] Add date-time parsing if the date API shape works well.
- [ ] Revisit URI parsing.

Open design questions:

- Which date/date-time types should be returned by default: `Date`, `DateTime`, or configurable target types?
- Should custom identifier parsers validate only syntax, normalize case/style, or return richer identifier wrapper types?
- Should any new value parser live behind optional extensions if it requires non-stdlib dependencies?


## Better taxonomy and generic traits for parsers

We should start defining abstract traits to lift some of the parsers behaviours in the
type system. This is long term.

