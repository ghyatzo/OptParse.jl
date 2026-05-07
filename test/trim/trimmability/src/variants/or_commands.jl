using OptParse

const show_cmd = command(
    "show",
    record((;
        kind = @constant(:show),
        id = arg(str()),
        verbose = optional(switch("-v", "--verbose")),
    ))
)

const edit_cmd = command(
    "edit",
    record((;
        kind = @constant(:edit),
        id = arg(str()),
        editor = optional(option("-e", "--editor", str())),
    ))
)

const parser = or(
    switch("-h", "--help"),
    option("-p", "--port", integer()),
    show_cmd,
    edit_cmd,
)

function @main(args::Vector{String})::Cint
    _ = optparse(parser, args)
    return 0
end
