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


@enum HelpEntryGroup::UInt8 begin
    HELP_Commands
    HELP_Arguments
    HELP_Options
    HELP_Other
end

@inline function _help_base_usage(node::UsageNode)::UsageNode
    kind = node.kind
    return if kind == USAGE_Optional || kind == USAGE_Repeat || kind == USAGE_Default || kind == USAGE_Hidden
        isempty(node.children) ? node : _help_base_usage(node.children[1])
    else
        node
    end
end

@inline function _help_entry_group(entry::HelpEntry)::HelpEntryGroup
    kind = _help_base_usage(entry.usage).kind
    return if kind == USAGE_Command
        HELP_Commands
    elseif kind == USAGE_Argument
        HELP_Arguments
    elseif kind == USAGE_Flag || kind == USAGE_Option
        HELP_Options
    else
        HELP_Other
    end
end

@inline _help_group_title(group::HelpEntryGroup) =
    group == HELP_Commands ? "Commands" :
    group == HELP_Arguments ? "Arguments" :
    group == HELP_Options ? "Options" :
    "Other"

@inline function _help_entry_label(entry::HelpEntry)
    usage = entry.usage
    base = _help_base_usage(usage)

    # Command listings should show only the command names; the full synopsis belongs
    # to the focused help page for that command, not to the parent command table.
    return if base.kind == USAGE_Command
        join(base.names, ", ")
    else
        render_usage(usage; style = :helplabel)
    end
end

@inline function _help_annotation(entry::HelpEntry)
    usage = entry.usage
    parts = String[]
    _usage_is_optional(usage) || push!(parts, "required")
    append!(parts, usage.annotations)
    base = _help_base_usage(usage)
    base === usage || append!(parts, base.annotations)
    return join(parts, "  ")
end

function render_help_entry(io::IO, entry::HelpEntry, usage_width::Int, leftpad::Int, desc_indent::Int)
    label = _help_entry_label(entry)
    annotation = _help_annotation(entry)
    brief = entry.info.brief

    print(io, " "^leftpad)
    print(io, label)

    if !isempty(annotation)
        gap = 4
        pad_to = leftpad + usage_width + gap
        current = leftpad + length(label)
        if current < pad_to
            print(io, " "^(pad_to - current))
        else
            print(io, "  ")
        end
        print(io, annotation)
    end
    println(io)

    if !isempty(brief)
        brief_lines = split(brief, '\n')
        indent = " "^(leftpad + desc_indent)
        for line in brief_lines
            println(io, indent, line)
        end
    end
    println(io)
    return nothing
end

function _render_help_group(io::IO, group::HelpEntryGroup, entries::Vector{HelpEntry}, leftpad::Int, desc_indent::Int)
    isempty(entries) && return nothing

    println(io, _help_group_title(group), ":")
    usage_width = maximum(length(_help_entry_label(entry)) for entry in entries)
    for entry in entries
        render_help_entry(io, entry, usage_width, leftpad, desc_indent)
    end
    return nothing
end

function _print_help_paragraph(io::IO, text::AbstractString)
    isempty(text) && return false
    println(io, text)
    return true
end


function render_helpdoc(doc::HelpDoc; progname = "")
    io = IOBuffer()
    render_helpdoc(io, doc; progname)
    return String(take!(io))
end

function render_helpdoc(io::IO, doc::HelpDoc; progname = "")
    info = doc.info
    entries = doc.entries

    groups = [HelpEntry[] for _ in 1:4]
    group_order = (
        HELP_Commands,
        HELP_Arguments,
        HELP_Options,
        HELP_Other,
    )

    for entry in entries
        push!(groups[Int(_help_entry_group(entry)) + 1], entry)
    end

    println(io)

    wrote_heading = false
    if !isempty(info.brief)
        println(io, info.brief)
        wrote_heading = true
    end
    if !isempty(info.description)
        wrote_heading && println(io)
        println(io, info.description)
        wrote_heading = true
    end

    wrote_heading && println(io)
    print(io, "Usage: ")
    render_usage(io, doc; style = :compact, progname)
    println(io)
    println(io)

    printed_group = false
    for group in group_order
        group_entries = groups[Int(group) + 1]
        isempty(group_entries) && continue
        _render_help_group(io, group, group_entries, 3, 4)
        printed_group = true
    end

    if !isempty(info.footer)
        (printed_group || wrote_heading || !isempty(entries)) && println(io)
        println(io, info.footer)
    end
    return nothing
end
