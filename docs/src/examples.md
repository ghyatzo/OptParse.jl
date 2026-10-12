# Examples

These recipes use the same field parsers inside [`@parser`](@ref) and
[`record`](@ref). See the [user guide](guide.md) for their composition rules.

## Typed configuration and help

```jldoctest
julia> using OptParse

julia> @parser struct Config
           @description "Greeting application"
           "Your name"
           name = option("-n", "--name", str("NAME"))
           "Enable verbose output"
           verbose = flag("-v", "--verbose")
           @footer "Pass --help for more information."
       end;

julia> result = optparse(Config, ["--name", "Alice", "-v"]);

julia> (result isa Config, result.name, result.verbose)
(true, "Alice", true)

julia> text = generate_help(lift(Config), String[]; progname="greet");

julia> all(phrase -> occursin(phrase, text), ["Greeting application", "Your name", "Pass --help"])
true
```

For application arguments, use `runparse(Config, ARGS; progname="greet")`.
Handle `nothing` before using the returned configuration.

## Shared options

Use `combine` to reuse field parsers across commands.
The field names in the combined records must be distinct.

```jldoctest
julia> using OptParse

julia> common = record(; verbose=flag("-v", "--verbose"));

julia> add = command("add", combine(
           common,
           record(; packages=many1(arg(str("PACKAGE")))),
       ));

julia> remove = command("remove", "rm", combine(
           common,
           record(; packages=many1(arg(str("PACKAGE")))),
       ));

julia> cli = or(add, remove);

julia> optparse(cli, ["add", "DataFrames", "Plots", "-v"])
(verbose = true, packages = ["DataFrames", "Plots"])

julia> optparse(cli, ["rm", "Plots"])
(verbose = false, packages = ["Plots"])
```

For command-specific result types and method dispatch, see
[typed subcommands](guide.md#Typed-subcommands).

## Option spellings and bundled flags

```jldoctest
julia> using OptParse

julia> port = option("-p", "--port", integer("PORT"));

julia> optparse(port, ["--port=8080"]) == optparse(port, ["-p", "8080"]) == 8080
true

julia> flags = record(;
           all = flag("-a"),
           long = flag("-l"),
           human = flag("-h"),
       );

julia> optparse(flags, ["-alh"])
(all = true, long = true, human = true)

julia> length(optparse(many(switch("-v")), ["-vvv"]))
3
```

## Positive and negative flags

[`toggle`](@ref) distinguishes an omitted flag from an explicit positive or
negative choice. Use a surrounding record when `nothing` also needs to be
distinguished from a failed `optparse` call.

```jldoctest
julia> using OptParse

julia> parser = record(; tags=toggle("--tags"));

julia> optparse(parser, String[]).tags === nothing
true

julia> optparse(parser, ["--tags"]).tags
true

julia> optparse(parser, ["--no-tags"]).tags
false

julia> using OptParse.SumResults: is_error

julia> is_error(tryoptparse(parser, ["--tags", "--no-tags"]))
true
```

## Constrained values

```jldoctest
julia> using OptParse

julia> @enum Mode Debug Release

julia> parser = record(;
           port = option("-p", integer("PORT"; min=1000, max=65535)),
           mode = option("--mode", choice("MODE", Mode)),
           config = option("-c", str("FILE"; pattern=r".*\.toml$")),
       );

julia> optparse(parser, ["-p", "8080", "--mode", "Debug", "-c", "server.toml"])
(port = 8080, mode = Debug, config = "server.toml")
```

## Dates and times

!!! warning "Trimming limitation"
    `dateformat`, `isodate`, and `isodatetime` do not support `juliac` trimming.
    Their underlying date/time parsing mechanism contains type instabilities.
    These parsers work in normal Julia applications.

Date parsers use `Dates.DateFormat` syntax and return `Date` or `DateTime` values.
The `after` and `before` bounds are inclusive. ISO defaults do not enforce fixed
field widths or require every trailing field. The supplied format defines the grammar.

```jldoctest
julia> using OptParse, Dates

julia> parser = record(;
           day = option("--day", isodate("DATE"; after=Date(2026, 1, 1))),
           at = option("--at", isodatetime("TIME")),
           report = option("--report", dateformat("REPORT", Date, "dd/mm/yyyy")),
       );

julia> config = optparse(parser, [
           "--day", "2026-04-15",
           "--at", "2026-04-15T09:30:00",
           "--report", "15/04/2026",
       ]);

julia> (config.day == Date(2026, 4, 15), config.at == DateTime(2026, 4, 15, 9, 30), config.report == config.day)
(true, true, true)
```

## Option terminator

After `--`, tokens that look like options or commands can be positional values.

```jldoctest
julia> using OptParse

julia> parser = or(
           command("test", record(; level=option("-v", integer("LEVEL")))),
           arg(str("ARG")),
       );

julia> optparse(parser, ["--", "test"])
"test"
```

## Complete application

For a CLI application with automatic help and subcommands, see
[`examples/HelloWorld/`](https://github.com/ghyatzo/OptParse.jl/tree/main/examples/HelloWorld).
