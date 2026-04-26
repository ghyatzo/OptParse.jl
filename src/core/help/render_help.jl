function render_usage(focused::HelpDoc; style::Symbol = :compact, progname::AbstractString = "")
    io = IOBuffer()
    render_usage(io, focused; style, progname)
    return String(take!(io))
end

function render_usage(io::IO, focused::HelpDoc; style::Symbol = :compact, progname::AbstractString = "")
    prefixed_progname = _usage_with_prefix(progname, focused.prefix)
    render_usage(io, focused.usage; style, progname = prefixed_progname)
    return nothing
end


function render_help_entry(io::IO, entry::HelpEntry)
    print(io, " ")
    render_usage(io, entry.usage)
    print(io, "\t\t")
    print(io, entry.info.brief)
    print(io, "\t\t")
    print(io, entry.info.description)
    println(io)
    return nothing
end


function render_helpdoc(doc::HelpDoc; progname = "")
    io = IOBuffer()
    render_helpdoc(io, doc; progname)
    return String(take!(io))
end

function render_helpdoc(io::IO, doc::HelpDoc; progname = "")
    usage = doc.usage
    info = doc.info

    println(io, info.brief)
    println(io, info.description)
    print(io, "Usage: ")
    render_usage(io, doc; style = :compact, progname)
    println(io)
    println(io)
    for entry in doc.entries
        render_help_entry(io, entry)
    end

    println(io, info.footer)
    return nothing
end
