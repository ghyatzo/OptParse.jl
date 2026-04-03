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
arg
cmd
@constant
```

### Value Parsers

```@docs
str
choice
integer
i8
i16
i32
i64
u8
u16
u32
u64
flt
flt32
flt64
uuid
path
```

### Modifiers

```@docs
default
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
