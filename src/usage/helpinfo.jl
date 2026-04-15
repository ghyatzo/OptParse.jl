Base.@kwdef struct HelpInfo
    hidden::Bool = false
    brief::String = ""
    description::String = ""
    footer::String = ""
end

HelpInfo(
    brief::AbstractString,
    description::AbstractString = "",
    footer::AbstractString = "";
    hidden::Bool = false
) = HelpInfo(
    hidden = hidden,
    brief = String(brief),
    description = String(description),
    footer = String(footer),
)

function merge_helpinfo(base::HelpInfo, overlay::HelpInfo)
    return HelpInfo(
        hidden = base.hidden || overlay.hidden,
        brief = isempty(overlay.brief) ? base.brief : overlay.brief,
        description = isempty(overlay.description) ? base.description : overlay.description,
        footer = isempty(overlay.footer) ? base.footer : overlay.footer,
    )
end

@inline _usage_or_hidden(info::HelpInfo, node::UsageNode) =
    info.hidden ? UsageHidden(node) : node
