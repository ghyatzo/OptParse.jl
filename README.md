# CLIpper
A Type Stable Composable CLI Parser inspired by [Optique](https://optique.dev/) and [optparse-applicative](https://github.com/pcapriotti/optparse-applicative).


## Quick Start

Here’s a minimal example of defining and parsing options:

```julia
using CLIpper

# Define a parser for two options: name and port
parser = object((
    name = option("-n", "--name", str()),
    port = option("-p", "--port", integer(min=1000))
))

# Parse arguments
args = ["--name", "server", "--port", "8080"]
result = argparse(parser, args)

@assert result.name == "server"
@assert result.port == 8080
```

---

## Example: Subcommands

CLIpper supports subcommands using combinators:

```julia
addCmd = command("add", object((
    action = @constant(:add),
    key = argument(str(metavar="KEY")),
    value = argument(str(metavar="VALUE"))
)))

removeCmd = command("remove", object((
    action = @constant(:remove),
    key = argument(str(metavar="KEY"))
)))

parser = or(addCmd, removeCmd)

# Parse: add key value
result = argparse(parser, ["add", "username", "me"])

@assert result.action == :add
@assert result.key == "username"
@assert result.value == "me"
```

---

## License

MIT License. See LICENSE for details.
