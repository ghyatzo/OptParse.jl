## Examples

### Basic Option Parsing

```julia
# Options with different styles
port = option("-p", "--port", integer())

result = argparse(port, ["--port=8080"])  # Long form with =
result = argparse(port, ["-p", "8080"])   # Short form
```

### Bundled Flags

```julia
# Flags can be bundled
parser = object((
    all = flag("-a"),
    long = flag("-l"),
    human = flag("-h")
))

result = argparse(parser, ["-alh"])  # Equivalent to ["-a", "-l", "-h"]
```

### Type Constraints

```julia
# Type-safe parsing with constraints
port = option("-p", integer(min=1000, max=65535))
level = option("-l", choice("debug", "info", "warn", "error"))
config = option("-c", str(pattern=r".*\.toml$"))
```

### Optional and Default Values

```julia
# Optional values
email = optional(option("-e", "--email", str()))

# With defaults
port = withDefault(option("-p", integer()), 8080)

# Multiple values
packages = multiple(argument(str()))  # pkg add Package1 Package2 Package3

# Verbosity levels
verbosity = multiple(flag("-v"))  # -v -v -v or -vvv
```

### Object Composition

```julia
parser = object((
    input = argument(str(metavar="INPUT")),
    output = option("-o", "--output", str()),
    force = switch("-f", "--force")
))

result = argparse(parser, ["input.txt", "-o", "output.txt", "-f"])
```

### Subcommands with or

```julia
# Define commands
addCmd = command("add", object((
    action = @constant(:add),
    packages = multiple(argument(str(metavar="PACKAGE")))
)))

removeCmd = command("remove", object((
    action = @constant(:remove),
    packages = multiple(argument(str(metavar="PACKAGE")))
)))

# Combine with or
pkgParser = or(addCmd, removeCmd)

# Parse
result = argparse(pkgParser, ["add", "DataFrames", "Plots"])
@assert result.action == :add
@assert result.packages == ["DataFrames", "Plots"]
```