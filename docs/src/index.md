# OptParse.jl

OptParse turns command-line arguments into typed Julia values. Define your CLI
with [`@parser`](@ref), including value constraints, defaults, and help text.

## Installation

Requires Julia 1.12 or later.

```julia
using Pkg
Pkg.add("OptParse")
```

## Define your CLI

```jldoctest getting-started
julia> using OptParse

julia> @parser struct Config
           @description "Development server"
           "Hostname to bind"
           host = option("--host", str("HOST")) |>
                default("localhost")
           "TCP port"
           port = option("-p", "--port", integer("PORT"; min=1, max=65535)) |>
                default(8080)
           "Enable verbose logging"
           verbose = flag("-v", "--verbose")
       end;

julia> config = optparse(Config, ["--port", "9000", "-v"]);

julia> (config isa Config, config.host, config.port, config.verbose)
(true, "localhost", 9000, true)
```

`@parser` defines a struct and its parser. Each field gets its type from the
corresponding parser expression. Strings before fields supply help text.
You can pass `Config` directly to the parsing entrypoints.

## Run an application

For a script named `server.jl`, use the definition above and pass Julia's `ARGS`
to [`runparse`](@ref):

```julia
config = runparse(Config, ARGS; progname="server")
if config !== nothing
    println("Server configuration: $(config.host):$(config.port)")
end
```

```sh
julia server.jl --port 9000 -v
julia server.jl --help
```

`runparse` adds automatic `--help` and `help` handling. With no arguments, it
shows help by default. It returns `nothing` after displaying help or a parse
error, so the application must handle that result before using the configuration.

## Quick scripts

If you do not need a named type, use [`record`](@ref). It returns a named tuple
and uses the same field parsers as `@parser`.

```jldoctest
julia> using OptParse

julia> parser = record(;
           input = arg(str("FILE")),
           verbose = flag("-v", "--verbose"),
       );

julia> optparse(parser, ["data.csv", "-v"])
(input = "data.csv", verbose = true)
```

Use `optparse(parser, ARGS)` for direct parsing, or `runparse(parser, ARGS)`
for automatic help.

## Next steps

- [User guide](guide.md): field parsers, composition, subcommands, help, and error handling.
- [Examples](examples.md): checked recipes for common CLI patterns.
- [API reference](reference.md): constructor signatures and keywords.
- [Development guide](development/index.md): parser internals and extension interfaces.

OptParse is inspired by [optparse-applicative](https://github.com/pcapriotti/optparse-applicative)
and [Optique](https://optique.dev/). It uses the [MIT License](https://github.com/ghyatzo/OptParse.jl/blob/main/LICENSE).
