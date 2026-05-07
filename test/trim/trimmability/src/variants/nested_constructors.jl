using OptParse

const sync_cmd = command(
    "sync",
    sequence(
        record((;
            source = option("--src", str()),
            dest = option("--dst", str()),
            force = default(switch("-f", "--force"), false),
        )),
        optional(option("-t", "--threads", integer(; min = 1, max = 16))),
    )
)

const status_cmd = command(
    "status",
    record((;
        long = optional(switch("-l", "--long")),
        json = default(switch("--json"), false),
    ))
)

const parser = or(sync_cmd, status_cmd)
# const parser = or(sync_cmd)

function @main(args::Vector{String})::Cint
    _ = optparse(parser, args)
    return 0
end
