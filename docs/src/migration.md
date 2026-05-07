# Migration Guide

This page collects public API renames that are easy to miss when upgrading
OptParse code. OptParse is still experimental, so this guide focuses on
mechanical source changes rather than long compatibility notes. Each section is
named after the version line that introduced the breaking changes.

## 0.3.x

These changes rename public constructors and keywords, but keep the underlying
parser behavior the same.

### Entry Points

| Old API | Use | Notes |
| --- | --- | --- |
| `argparse(parser, argv)` | `optparse(parser, argv)` | High-level throwing parse entrypoint. |
| `tryargparse(parser, argv)` | `tryoptparse(parser, argv)` | Lower-level non-throwing parse entrypoint. |
| `gate(...)` | `switch(...)` | Required presence parser. |

### Constructors

| Old API | Use | Notes |
| --- | --- | --- |
| `object((...))` | `record((...))` | Builds a named-tuple parser. |

Before:

```julia
parser = object((
    host = option("--host", str("HOST")),
    port = option("--port", integer("PORT")),
))
```

After:

```julia
parser = record((
    host = option("--host", str("HOST")),
    port = option("--port", integer("PORT")),
))
```

### Repetition

| Old API | Use | Notes |
| --- | --- | --- |
| `multiple(p)` | `many(p)` | Zero or more matches. |
| `multiple(p; min = 0)` | `many(p)` | Zero or more matches. |
| `multiple(p; min = 1)` | `many1(p)` | One or more matches. |
| `multiple(p; min = lo, max = hi)` | `repeated(p; min = lo, max = hi)` | Explicit bounded repetition. |

Before:

```julia
packages = multiple(arg(str("PACKAGE")))
files = multiple(arg(str("FILE")); min = 1)
includes = multiple(option("-I", str("DIR")); min = 1, max = 3)
```

After:

```julia
packages = many(arg(str("PACKAGE")))
files = many1(arg(str("FILE")))
includes = repeated(option("-I", str("DIR")); min = 1, max = 3)
```

Use `many` when an empty vector is valid, `many1` when at least one match is
required, and `repeated` when the bounds should be visible at the call site.

### Keyword Arguments

| Old keyword | Use | Applies to |
| --- | --- | --- |
| `caseInsensitive` | `case_insensitive` | [`choice`](@ref) |
| `allowInfinity` | `allow_infinity` | [`flt`](@ref), [`flt32`](@ref), [`flt64`](@ref) |
| `allowNan` | `allow_nan` | [`flt`](@ref), [`flt32`](@ref), [`flt64`](@ref) |
| `allowedVersions` | `allowed_versions` | [`uuid`](@ref) |

Before:

```julia
mode = choice("MODE", ["debug", "release"]; caseInsensitive = true)
ratio = flt("RATIO"; allowInfinity = true, allowNan = false)
id = uuid("ID"; allowedVersions = [4])
```

After:

```julia
mode = choice("MODE", ["debug", "release"]; case_insensitive = true)
ratio = flt("RATIO"; allow_infinity = true, allow_nan = false)
id = uuid("ID"; allowed_versions = [4])
```

## 0.2.x

The `0.2.0` changelog introduced several public API renames.

| Old API | Use | Notes |
| --- | --- | --- |
| `argument(...)` | `arg(...)` | Positional argument parser. |
| `withDefault(p, value)` | `default(p, value)` | Default-value modifier. |
| `switch(...)` | `flag(...)` | Optional boolean flag that defaults to `false`. |
| `flag(...)` | `gate(...)` | Required presence parser. Renamed again to `switch(...)` in `0.3.x`. |
| `objmerge(...)` | `combine(...)` | Merge record-like parser groups. |
| `tup(...)` | `sequence(...)` | Ordered tuple parser. |
| `cmd(...)` | `command(...)` | The temporary `command` to `cmd` rename was reverted. |

The `flag` and `gate` rename is the only entry in this table where semantics can
be confused by the old name. If the old parser represented an optional boolean,
use `flag`. If it represented a required presence check, use `gate` for `0.2.x`
or `switch` for `0.3.x`.
