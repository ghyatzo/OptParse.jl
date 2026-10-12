<p align="center">
  <img src="docs/src/assets/logo.svg" alt="OptParse logo" width="420">
</p>

# OptParse.jl

OptParse turns command-line arguments into typed Julia values. Define your CLI with
`@parser`, including value constraints, defaults, and help text.

[![Build Status](https://github.com/ghyatzo/OptParse.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/ghyatzo/OptParse.jl/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/gh/ghyatzo/OptParse.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/ghyatzo/OptParse.jl)
[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)
[![Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://ghyatzo.github.io/OptParse.jl/dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

## Installation

Requires Julia 1.12 or later.

```julia
using Pkg
Pkg.add("OptParse")
```

## Define your CLI with `@parser`

```julia
using OptParse

@parser struct Config
    @description "Development server"

    "Hostname to bind"
    host = default(option("--host", str("HOST")), "localhost")

    "TCP port"
    port = default(
        option("-p", "--port", integer("PORT"; min=1, max=65535)),
        8080,
    )

    "Enable verbose logging"
    verbose = flag("-v", "--verbose")
end

config = optparse(Config, ["--port", "9000", "-v"])

@assert config isa Config
@assert config.host == "localhost"
@assert config.port == 9000
@assert config.verbose
```

`@parser` defines a struct and its parser. Each field gets its type from the
corresponding parser expression. Strings before fields supply help text.

For a command-line application, pass Julia's `ARGS` to `runparse`:

```julia
config = runparse(Config, ARGS; progname="server")
```

`runparse` adds automatic `--help` and `help` handling. With no arguments, it
shows help by default. It returns `nothing` after displaying help or a parse
error. Only use the returned configuration when it is not `nothing`.

For example, these invocations parse a configuration or show help:

```sh
julia server.jl --port 9000 -v
julia server.jl --help
```

## Quick scripts with `record`

If you do not need a named type, use `record`. It returns a named tuple and
uses the same field parsers as `@parser`.

```julia
using OptParse

parser = record(;
    input = arg(str("FILE")),
    verbose = flag("-v", "--verbose"),
)

config = optparse(parser, ["data.csv", "-v"])

@assert config == (input="data.csv", verbose=true)
```

Use `optparse(parser, ARGS)` for direct parsing, or `runparse(parser, ARGS)`
for automatic help.

## Extend your parser

Field definitions compose from smaller parsers. These expressions work inside
both `@parser` and `record`:

| Need | Field definition |
|------|------------------|
| Required option | `name = option("--name", str("NAME"))` |
| Optional option | `output = optional(option("-o", str("FILE")))` |
| Default value | `port = default(option("--port", integer("PORT")), 8080)` |
| Boolean flag | `verbose = flag("-v", "--verbose")` |
| Restricted values | `mode = option("--mode", choice("MODE", ["fast", "safe"]))` |
| Positional argument | `input = arg(str("FILE"))` |
| One or more arguments | `files = many1(arg(str("FILE")))` |

Options and positional arguments are required unless wrapped in `optional`,
`default`, or a modifier that permits zero matches. Flags default to `false`.
Names such as `"FILE"` and `"PORT"` are placeholders in usage and help output.

### Subcommands

Use `lift` to retrieve the parser associated with an `@parser` type. Wrap it
in `command` and combine alternative commands with `or`:

```julia
using OptParse

@parser struct Greet
    "Name to greet"
    name = arg(str("NAME"))
end

@parser struct Add
    "Numbers to add"
    numbers = many1(arg(integer("NUMBER")))
end

cli = or(
    command("greet", lift(Greet)),
    command("add", lift(Add)),
)

result = optparse(cli, ["greet", "Ada"])
@assert result isa Greet
@assert result.name == "Ada"

result = optparse(cli, ["add", "2", "3"])
@assert result isa Add
@assert sum(result.numbers) == 5
```

Each command returns its own type, so application methods can dispatch on
`Greet` or `Add`. `runparse` also provides help for individual subcommands.

```julia
doaction(r::Greet) = println("Hello, $(r.name)")
doaction(r::Add) = println("Your result is $(sum(r.numbers))")

runparse(cli, ["greet", "--help"]; progname="demo")
runparse(cli, ["add", "3", "4"]; progname="demo") |> doaction
# Your result is 7
```

`or` tries branches in order. Put broad positional alternatives last.

### Argument syntax

- Long options accept `--port 9000` or `--port=9000`.
- Short option names contain one letter. Separate their values: `-p 9000`, not `-p9000`.
- Short boolean flags can be bundled: `-abc` means `-a -b -c`.
- `--` stops option recognition. Tokens after it are available to positional parsers.

## Parsing and errors

All three entrypoints accept an `@parser` type or a parser object:

| Entrypoint | Behavior |
|------------|----------|
| `optparse(Config, argv)` | Returns a value, or prints a parse error to `stderr` and returns `nothing`. |
| `runparse(Config, argv; ...)` | Adds automatic help to `optparse`. Returns `nothing` after displaying help. |
| `tryoptparse(Config, argv)` | Returns a result container with a value or a structured parse error. |

Use `tryoptparse` to handle parse errors programmatically.

## Learn more

The [documentation](https://ghyatzo.github.io/OptParse.jl/dev/) covers parser
composition, help, and application behavior.

- [Examples](https://ghyatzo.github.io/OptParse.jl/dev/examples/)
- [API reference](https://ghyatzo.github.io/OptParse.jl/dev/reference/) — value parsers,
  modifiers, `construct`, `construct_exact`, and partial parsing
- [Inference and trimming](https://ghyatzo.github.io/OptParse.jl/dev/development/inference/)
  — type stability and the `juliac` preference for compiled applications

Docstrings are also available through Julia's help system: `?@parser`,
`?option`, and `?record`.

## Contributing

Issues and pull requests are welcome.

## License

MIT License. See [LICENSE](LICENSE).

## Acknowledgments

OptParse is inspired by [optparse-applicative](https://github.com/pcapriotti/optparse-applicative)
and [Optique](https://optique.dev/).
