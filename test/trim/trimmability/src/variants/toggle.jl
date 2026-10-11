using OptParse

const parser = record(;
    tags = toggle("--tags"),
    name = default(option("-n", "--name", str()), "world"),
    verbose = switch("-v", "--verbose"),
)

function @main(args::Vector{String})::Cint
    _ = optparse(parser, args)
    return 0
end
