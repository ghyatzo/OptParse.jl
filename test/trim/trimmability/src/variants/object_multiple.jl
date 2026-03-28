using OptParse

const parser = object((;
    names = multiple(option("-n", "--name", str()); min = 1, max = 3),
    level = withDefault(option("-l", "--level", integer(; min = 1, max = 5)), 3),
    dryrun = withDefault(flag("--dry-run"), false),
    tags = multiple(argument(str()); min = 1, max = 2),
))

function @main(args::Vector{String})::Cint
    _ = cliargparse(parser, args)
    return 0
end
