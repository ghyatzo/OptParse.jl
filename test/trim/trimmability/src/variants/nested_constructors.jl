using OptParse

const sync_cmd = command(
    "sync",
    sequence(
        object((;
            source = option("--src", str()),
            dest = option("--dst", str()),
            force = default(gate("-f", "--force"), false),
        )),
        optional(option("-t", "--threads", integer(; min = 1, max = 16))),
    )
)

const status_cmd = command(
    "status",
    object((;
        long = optional(gate("-l", "--long")),
        json = default(gate("--json"), false),
    ))
)

# const parser = or(sync_cmd, status_cmd)
const parser = or(sync_cmd)

function @main(args::Vector{String})::Cint
    _ = optparse(parser, args)
    return 0
end
