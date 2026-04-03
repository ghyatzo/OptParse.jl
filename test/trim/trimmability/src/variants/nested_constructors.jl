using OptParse

const sync_cmd = cmd(
    "sync",
    sequence(
        object((;
            source = option("--src", str()),
            dest = option("--dst", str()),
            force = default(flag("-f", "--force"), false),
        )),
        optional(option("-t", "--threads", integer(; min = 1, max = 16))),
    )
)

const status_cmd = cmd(
    "status",
    object((;
        long = optional(flag("-l", "--long")),
        json = default(flag("--json"), false),
    ))
)

# const parser = or(sync_cmd, status_cmd)
const parser = or(sync_cmd)

function @main(args::Vector{String})::Cint
    _ = argparse(parser, args)
    return 0
end
