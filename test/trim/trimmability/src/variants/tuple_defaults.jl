using OptParse

const parser = tup(
    argument(str()),
    withDefault(option("-n", "--num", integer()), 10),
    optional(flag("-v", "--verbose")),
    withDefault(option("--mode", choice(["fast", "safe"])), "safe"),
)

function @main(args::Vector{String})::Cint
    _ = argparse(parser, args)
    # println(Core.stdout, join(args, ','))
    return 0
end
