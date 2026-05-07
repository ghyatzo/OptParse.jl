using OptParse

const parser = object((;
    names = repeated(option("-n", "--name", str()); min = 1, max = 3),
    level = default(option("-l", "--level", integer(; min = 1, max = 5)), 3),
    dryrun = default(switch("--dry-run"), false),
    tags = repeated(arg(str()); min = 1, max = 2),
))

function @main(args::Vector{String})::Cint
    _ = optparse(parser, args)
    return 0
end
