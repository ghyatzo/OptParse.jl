# User guide

Start with the [`@parser` example](index.md). The same field expressions work
inside `@parser` definitions and [`record`](@ref) parsers.

## Field parsers

A field parser describes command-line syntax and the value it produces.
For example, `option("--port", integer("PORT"))` matches an option and converts
its value to an integer.

| Syntax | Parser | Result |
|--------|--------|--------|
| `--name Ada` | `option("--name", str("NAME"))` | `String` |
| `--port 9000` | `option("--port", integer("PORT"; min=1, max=65535))` | `Int` |
| `--verbose` | `flag("-v", "--verbose")` | `Bool`, default `false` |
| `--tags` / `--no-tags` | `toggle("--tags")` | `true`, `false`, or `nothing` |
| `data.csv` | `arg(str("FILE"))` | `String` |

Options and positional arguments are required unless a modifier permits their
absence. [`switch`](@ref) is a required presence flag, unlike [`flag`](@ref).

### Value conversion and constraints

Value parsers convert individual string tokens. Use them inside `option` or
`arg` to match command-line input.

- [`str`](@ref) parses strings and supports pattern constraints.
- [`integer`](@ref), [`i32`](@ref), and related constructors parse integers with optional bounds.
- [`flt`](@ref), [`flt32`](@ref), and [`flt64`](@ref) parse floating-point numbers.
- [`choice`](@ref) restricts input to listed strings or enum values.
- [`uuid`](@ref) and [`path`](@ref) parse UUIDs and filesystem paths.
- [`isodate`](@ref), [`isodatetime`](@ref), and [`dateformat`](@ref) parse dates and times.

Names such as `"FILE"` and `"PORT"` are placeholders in usage and help output.
The positional placeholder form is the preferred API.

```jldoctest
julia> using OptParse

julia> mode = option("--mode", choice("MODE", ["fast", "safe"]));

julia> optparse(mode, ["--mode", "safe"])
"SAFE"
```

String choices are case-insensitive by default and return uppercase strings.
Pass `case_insensitive=false` to preserve the listed spelling and require exact case.
Enum choices return enum values instead of strings.

## Defaults, optional fields, and repetition

Modifiers wrap a field parser:

| Modifier | Behavior |
|----------|----------|
| `default(p, value)` | Returns `value` when `p` does not match. |
| `optional(p)` | Equivalent to `default(p, nothing)`. |
| `many(p)` | Returns a vector of zero or more matches. |
| `many1(p)` | Requires at least one match. |
| `repeated(p; min, max)` | Sets explicit repetition bounds. |

```jldoctest
julia> using OptParse

julia> @parser struct Inputs
           output = optional(option("-o", str("FILE")))
           files = many1(arg(str("FILE")))
           verbosity = many(switch("-v"))
       end;

julia> inputs = optparse(Inputs, ["a.csv", "b.csv", "-vv"]);

julia> (inputs.output, inputs.files, length(inputs.verbosity))
(nothing, ["a.csv", "b.csv"], 2)
```

Use `many(switch("-v"))` for repeated verbosity flags. Each matched flag
contributes one element, so `length` gives the verbosity level.

## Typed subcommands

[`lift`](@ref) retrieves the parser associated with an `@parser` type.
Wrap that parser in [`command`](@ref) and combine commands with [`or`](@ref).

```jldoctest typed-commands
julia> using OptParse

julia> @parser struct Greet
           "Name to greet"
           name = arg(str("NAME"))
       end;

julia> @parser struct Add
           "Numbers to add"
           numbers = many1(arg(integer("NUMBER")))
       end;

julia> cli = or(
           command("greet", lift(Greet)),
           command("add", lift(Add)),
       );

julia> greet = optparse(cli, ["greet", "Ada"]);

julia> (greet isa Greet, greet.name)
(true, "Ada")

julia> add = optparse(cli, ["add", "2", "3"]);

julia> (add isa Add, sum(add.numbers))
(true, 5)

julia> handle(x::Greet) = "Hello, $(x.name)";

julia> handle(x::Add) = sum(x.numbers);

julia> (handle(greet), handle(add))
("Hello, Ada", 5)
```

`or` tries branches in the order supplied. The first semantic match selects a
branch, and subsequent tokens stay within that branch. Put broad positional
alternatives last.

### Anonymous composition

Use [`record`](@ref) for named tuples and [`sequence`](@ref) for tuples.
[`combine`](@ref) merges record groups with distinct field names.
[`concat`](@ref) joins sequence groups.

Records allow options and positional arguments to appear together.
Result fields retain definition order. Matching uses parser priority, so explicit
options take precedence over broad positional parsers.

See [shared options](examples.md#Shared-options) for a `combine` example.

## Help and application behavior

Inside `@parser`, a string before a field supplies its brief help text.
`@description` and `@footer` annotate the whole parser.

Attach help to any parser with `parser |> help("Summary")`, or call
`help(parser, "Summary")` directly. The optional `description` and `footer`
keywords add longer text to that parser's help page without changing parsing.

For a summary in the parent command list, attach `help` to `command(...)`.
For the selected command's description and footer, annotate its child parser:

```jldoctest typed-commands
julia> greet_body = lift(Greet) |> help(;
           description="Print a greeting for the supplied name.",
           footer="Names with spaces must be quoted in the shell.",
       );

julia> greet_command = command("greet", greet_body) |> help("Greet someone");

julia> described_cli = or(greet_command, command("add", lift(Add)));

julia> occursin("Greet someone", generate_help(described_cli, String[]))
true

julia> text = generate_help(described_cli, ["greet"]);

julia> occursin("Print a greeting", text) && occursin("Names with spaces", text)
true
```

For an option or argument, attach it to the field parser, for example
`option("--port", integer("PORT")) |> help("TCP port")`.
Help information belongs to the annotated parser, not its children.
Use [`hidden`](@ref) to omit a parser from usage and help output without disabling it.

[`runparse`](@ref) adds application behavior without changing the parser definition:

| Keyword | Default | Purpose |
|---------|---------|---------|
| `progname` | `""` | Prefix for usage output. |
| `help_flags` | `["--help"]` | Help flags recognized before `--`. |
| `help_command` | `"help"` | Top-level help command. Use `""` to disable it. |
| `on_empty` | `[help_command]`, or `[]` if disabled | Arguments used for an empty invocation. |

For the `cli` above, `runparse(cli, ["greet", "--help"]; progname="demo")`
shows help for `greet`. `runparse(cli, ["help", "greet"]; progname="demo")`
shows the same command help.

To parse defaults instead of displaying help on an empty invocation, pass
`on_empty=String[]`. Help and parse errors go to `stderr`; both return `nothing`.
`runparse` does not exit the process or choose an exit code.

For explicit control, [`generate_help`](@ref) returns help text and
[`print_help`](@ref) writes it to an `IO`. [`helpcommand`](@ref) parses a
positional help request into a [`HelpRequest`](@ref).

```jldoctest typed-commands
julia> occursin("Name to greet", generate_help(cli, ["greet"]; progname="demo"))
true
```

## Parsing and errors

All three entrypoints accept an `@parser` type or a parser object:

- [`optparse`](@ref) returns a parsed value. On a parse error, it prints the
  error and focused usage to `stderr`, then returns `nothing`.
- [`runparse`](@ref) adds automatic help to `optparse`.
- [`tryoptparse`](@ref) returns a result container with either the value or a
  structured parse error. It does not print or throw for parse errors.

These parse-error behaviors are the same in both `juliac` modes.
Invalid parser definitions and unexpected implementation errors can still throw.

Import result helpers explicitly from `OptParse.SumResults`:

```jldoctest
julia> using OptParse

julia> using OptParse.SumResults: is_error, unwrap, unwrap_error

julia> port = option("--port", integer("PORT"; min=1, max=65535));

julia> success = tryoptparse(port, ["--port", "9000"]);

julia> (is_error(success), unwrap(success))
(false, 9000)

julia> failure = tryoptparse(port, ["--port", "invalid"]);

julia> is_error(failure)
true

julia> unwrap_error(failure) isa OptParse.AbstractParseError
true
```

OptParse exports `@?` for early-return error propagation. Other result helpers,
including `Ok` and `Err`, require an explicit import.

## Construct an existing type

Use `@parser` when the CLI definition also defines the application type.
For an existing struct, use [`construct`](@ref) or [`construct_exact`](@ref).

`construct` delegates to StructUtils. In normal Julia mode, it supports custom
StructUtils integration and dynamic parametric construction.
In `juliac` mode, the target type must be concrete.

`construct_exact` requires a concrete target type. Record field names and order
must match the struct. Sequence arity must match, and output types must be
subtypes of the corresponding field types. `@parser` uses this exact path.

```jldoctest
julia> using OptParse

julia> struct ServerConfig
           host::String
           port::Int
       end

julia> parser = construct_exact(ServerConfig, record(;
           host = default(option("--host", str("HOST")), "localhost"),
           port = default(option("--port", integer("PORT")), 8080),
       ));

julia> config = optparse(parser, ["--port", "9000"]);

julia> (config.host, config.port)
("localhost", 9000)
```

## Partial parsing

[`partial`](@ref) supports wrapper CLIs that pass unrecognized tokens to another
program. With `tryoptparse`, it returns an ordinary `(value, remaining)` tuple
inside a result container.

```jldoctest
julia> using OptParse

julia> using OptParse.SumResults: unwrap

julia> wrapper = partial(record(;
           verbose = flag("-v", "--verbose"),
           config = optional(option("-c", str("FILE"))),
       ));

julia> value, remaining = unwrap(tryoptparse(wrapper, ["-v", "--child-flag", "somefile"]));

julia> value == (verbose=true, config=nothing)
true

julia> remaining
2-element Vector{String}:
 "--child-flag"
 "somefile"
```

Unrecognized tokens are skipped and returned. Recognized inputs with invalid
values still produce errors, and required fields must still complete successfully.

## Argument syntax

- Long options accept `--port 9000` or `--port=9000`.
- Short option names contain one letter. Separate their values: `-p 9000`, not `-p9000`.
- Short boolean flags can be bundled: `-abc` means `-a -b -c`.
- `--` stops option and command recognition. Tokens after it are available to positional parsers.

For other value types and modifier keywords, see the [API reference](reference.md).
