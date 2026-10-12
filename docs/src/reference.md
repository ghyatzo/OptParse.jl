# API reference

See the [user guide](guide.md) for composition and application behavior.

## Typed parser definitions

```@docs
@parser
lift
AbstractLiftedParser
```

## Entry points

All three entrypoints accept a parser object or a type defined with `@parser`.
`optparse` prints parse errors to `stderr` and returns `nothing` on failure.
`runparse` adds automatic help. `tryoptparse` returns a result container without
printing parse errors. These behaviors do not depend on the `juliac` preference.

```@docs
optparse
tryoptparse
runparse
partial
valuetype
OptParse.ParseException
generate_help
print_help
HelpRequest
```

## Result containers (`OptParse.SumResults`)

```@docs
OptParse.SumResults
OptParse.SumResults.Result
OptParse.SumResults.Option
OptParse.SumResults.some
OptParse.SumResults.none
OptParse.SumResults.base
OptParse.SumResults.is_error
OptParse.SumResults.is_ok_and
OptParse.SumResults.unwrap
OptParse.SumResults.unwrap_error
OptParse.SumResults.@?
```

## Primitives

```@docs
option
flag
switch
toggle
arg
command
helpcommand
@constant
```

## Value parsers

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
dateformat
isodate
isodatetime
```

## Modifiers

```@docs
default
optional
repeated
many
many1
construct
construct_exact
help
hidden
```

## Constructors

```@docs
record
combine
or
sequence
concat
```

## Development utilities

```@docs
OptParse.validate
```
