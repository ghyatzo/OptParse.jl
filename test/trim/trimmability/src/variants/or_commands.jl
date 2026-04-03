using OptParse

const show_cmd = cmd(
    "show",
    object((;
        kind = @constant(:show),
        id = arg(str()),
        verbose = optional(gate("-v", "--verbose")),
    ))
)

const edit_cmd = cmd(
    "edit",
    object((;
        kind = @constant(:edit),
        id = arg(str()),
        editor = optional(option("-e", "--editor", str())),
    ))
)

const parser = or(
    gate("-h", "--help"),
    option("-p", "--port", integer()),
    show_cmd,
    edit_cmd,
)

function @main(args::Vector{String})::Cint
    _ = argparse(parser, args)
    return 0
end
