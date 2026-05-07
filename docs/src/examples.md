## Examples

### Basic Option Parsing

```julia
# Options with different styles
port = option("-p", "--port", integer("PORT"))

result = optparse(port, ["--port=8080"])  # Long form with =
result = optparse(port, ["-p", "8080"])   # Short form
```

### Bundled Flags

```julia
# Flags can be bundled
parser = object((
    all = flag("-a"),
    long = flag("-l"),
    human = flag("-h")
))

result = optparse(parser, ["-alh"])  # Equivalent to ["-a", "-l", "-h"]
```

### Options Terminator

```julia
# After `--`, flags and options stop being recognized
parser = or(
    command("test", object((opt = option("-v", integer("LEVEL")),))),
    arg(str("ARG"))
)

result = optparse(parser, ["--", "test"])  # "test"
```

### Type Constraints

```julia
# Type-safe parsing with constraints
port = option("-p", integer("PORT"; min=1000, max=65535))
level = option("-l", choice("LEVEL", ["debug", "info", "warn", "error"]))
config = option("-c", str("FILE"; pattern=r".*\.toml$"))

@enum Mode begin
    Debug
    Release
end

mode = option("--mode", choice("MODE", Mode))
```

### Optional and Default Values

```julia
# Optional values (`optional(p)` is equivalent to `default(p, nothing)`)
email = optional(option("-e", "--email", str("EMAIL")))

# With defaults
port = default(option("-p", integer("PORT")), 8080)

# Repeated values
packages = many(arg(str("PACKAGE")))  # pkg add Package1 Package2 Package3

# Verbosity levels
verbosity = many(flag("-v"))  # -v -v -v or -vvv

# One or more values
files = many1(arg(str("FILE")))
```

### Object Composition

```julia
parser = object((
    input = arg(str("INPUT")),
    output = option("-o", "--output", str("OUTPUT")),
    force = flag("-f", "--force")
))

result = optparse(parser, ["input.txt", "-o", "output.txt", "-f"])
```

### Subcommands with or

```julia
# Define commands
addCmd = command("add", object((
    action = @constant(:add),
    packages = many(arg(str("PACKAGE")))
)))

removeCmd = command("remove", object((
    action = @constant(:remove),
    packages = many(arg(str("PACKAGE")))
)))

# Combine with or
pkgParser = or(addCmd, removeCmd)

# Parse
result = optparse(pkgParser, ["add", "DataFrames", "Plots"])
@assert result.action == Val(:add)
@assert result.packages == ["DataFrames", "Plots"]
```
