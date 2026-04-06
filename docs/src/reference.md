## API Reference

### Entry Points

- `optparse(parser, argv)` is the high-level convenience entrypoint
- in normal Julia runtime usage, `optparse` returns the parsed value or throws `OptParse.ParseException`
- when `juliac` mode is enabled through the `juliac` preference, `optparse` renders the error to `stderr` and returns `nothing` on failure instead of throwing
- `tryoptparse(parser, argv)` is the lower-level entrypoint and returns a result object instead of throwing

```@docs
optparse
tryoptparse
resulttype
OptParse.ParseException
```

### Primitives

```@docs
option
flag
gate
arg
command
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
combine
or
sequence
concat
```
