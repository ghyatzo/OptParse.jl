using OptParse

const parser = sequence(
    arg(str()),
    default(option("-n", "--num", integer()), 10),
    optional(gate("-v", "--verbose")),
    default(option("--mode", choice(["fast", "safe"])), "safe"),
)

function @main(args::Vector{String})::Cint
    _ = optparse(parser, args)
    # println(Core.stdout, join(args, ','))
    return 0
end
