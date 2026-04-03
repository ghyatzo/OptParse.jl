using OptParse

const parser = object((;
    names = multiple(option("-n", "--name", str()); min = 1, max = 3),
    level = default(option("-l", "--level", integer(; min = 1, max = 5)), 3),
    dryrun = default(gate("--dry-run"), false),
    tags = multiple(arg(str()); min = 1, max = 2),
))

function @main(args::Vector{String})::Cint
    _ = argparse(parser, args)
    return 0
end
