## API Reference

### Entry Points

- `argparse(parser, argv)` returns the parsed value or throws `OptParse.ParseException`
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
