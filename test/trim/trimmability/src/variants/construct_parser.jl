using OptParse

struct RemoteConfig
    host::String
    port::Int
    verbose::Bool
end

struct Coordinates{T<:Number}
    x::T
    y::T
end

const config_cmd = command(
    "config",
    construct(RemoteConfig, (;
        host = option("--host", str()),
        port = default(option("--port", integer()), 8080),
        verbose = flag("-v", "--verbose"),
    ))
)

const coords_cmd = command(
    "coords",
    construct(Coordinates{Int}, (
        arg(integer("X")),
        arg(integer("Y")),
    ))
)

const parser = or(config_cmd, coords_cmd)

function @main(args::Vector{String})::Cint
    _ = optparse(parser, args)
    return 0
end
