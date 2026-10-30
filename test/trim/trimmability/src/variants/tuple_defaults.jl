using OptParse

const parser = sequence(
    arg(str()),
    default(option("-n", "--num", integer()), 10),
    optional(switch("-v", "--verbose")),
    default(option("--mode", choice(["fast", "safe"])), "safe"),
    optional(option("--coords", list(integer(), 2))),
    optional(option("--bind", list(str(), integer(); separator = ':'))),
    optional(option("--origin", pair(str(), list(integer(), integer())))),
    default(option("--anchor", pair(str(), list(integer(), integer()))), "x" => (1, 2)),
)

function @main(args::Vector{String})::Cint
    if "--help" in args
        print_help(Core.stdout, parser, String[])
    else
        _ = optparse(parser, args)
    end
    return 0
end
