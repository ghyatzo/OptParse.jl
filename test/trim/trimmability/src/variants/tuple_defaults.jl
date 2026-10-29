using OptParse

const parser = sequence(
    arg(str()),
    default(option("-n", "--num", integer()), 10),
    optional(switch("-v", "--verbose")),
    default(option("--mode", choice(["fast", "safe"])), "safe"),
    optional(option("--coords", list(integer(), 2))),
    optional(option("--bind", list(str(), integer(); separator = ':'))),
)

function @main(args::Vector{String})::Cint
    _ = optparse(parser, args)
    # println(Core.stdout, join(args, ','))
    return 0
end
