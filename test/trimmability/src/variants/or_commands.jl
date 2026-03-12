using OptParse

const show_cmd = command(
    "show",
    object((;
        kind = @constant(:show),
        id = argument(str()),
        verbose = optional(flag("-v", "--verbose")),
    ))
)

const edit_cmd = command(
    "edit",
    object((;
        kind = @constant(:edit),
        id = argument(str()),
        editor = optional(option("-e", "--editor", str())),
    ))
)

const parser = or(
    flag("-h", "--help"),
    option("-p", "--port", integer()),
    show_cmd,
    edit_cmd,
)

function @main(args::Vector{String})::Cint
    _ = @? argparse(parser, args)
    return 0
end
