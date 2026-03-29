## API Reference

### Entry Points

- `argparse(parser, argv)` is the high-level convenience entrypoint
- in normal Julia runtime usage, `argparse` returns the parsed value or throws `OptParse.ParseException`
- when compiled while `Base.generating_output()` is true, `argparse` renders the error to `stderr` and returns `nothing` on failure instead of throwing
- `tryargparse(parser, argv)` is the lower-level entrypoint and returns a result object instead of throwing

```@docs
argparse
tryargparse
OptParse.ParseException
```

### Primitives

```@docs
option
flag
switch
argument
command
@constant
```

### Modifiers

```@docs
withDefault
optional
multiple
```

### Constructors

```@docs
object
objmerge
or
tup
concat
```
