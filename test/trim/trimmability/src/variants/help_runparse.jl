using OptParse

@parser struct ServeCmd
    @description "Start the HTTP server"
    @footer "Example: app serve --host 0.0.0.0 -p 8080"

    "Host address to bind"
    host = default(option("-H", "--host", str("HOST")), "127.0.0.1")

    "Port number"
    port = default(option("-p", "--port", integer("PORT"; min = 1, max = 65535)), 8080)

    "Enable verbose logging"
    verbose = flag("-v", "--verbose")
end

@parser struct CheckCmd
    @description "Validate a configuration file"

    "Configuration file path"
    file = arg(str("FILE"))

    "Strict mode"
    strict = switch("--strict")
end

const parser = or(
    command("serve", lift(ServeCmd)) |> help("Run the server"),
    command("check", lift(CheckCmd)) |> help("Check configuration"),
) |> help(
    "App CLI",
    description = "Application with built-in help and subcommands.",
    footer = "Run `app help <command>` for subcommand details.",
)

function @main(args::Vector{String})::Cint
    res = runparse(parser, args; progname = "app")
    isnothing(res) && return 1
    print_help(Core.stdout, parser, args; progname = "app")
    return 0
end
