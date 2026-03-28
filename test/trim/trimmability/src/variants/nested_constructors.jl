using OptParse

const sync_cmd = command(
    "sync",
    tup(
        object((;
            source = option("--src", str()),
            dest = option("--dst", str()),
            force = withDefault(flag("-f", "--force"), false),
        )),
        optional(option("-t", "--threads", integer(; min = 1, max = 16))),
    )
)

const status_cmd = command(
    "status",
    object((;
        long = optional(flag("-l", "--long")),
        json = withDefault(flag("--json"), false),
    ))
)

# const parser = or(sync_cmd, status_cmd)
const parser = or(sync_cmd)

function @main(args::Vector{String})::Cint
    _ = cliargparse(parser, args)
    return 0
end
