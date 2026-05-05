# The HelpInfo object holds auxiliary information used in the rendering of help messages.
# This is associated to a parser node by means of the Help Overlay.
# The help overlay should be the only one modifying this information.
# Help information in principle is not really associated to a specific kind of node but
# through the overlay mechanism each node can have help information associated in their context.

Base.@kwdef struct HelpInfo
    hidden::Bool = false
    brief::String = ""
    description::String = ""
    footer::String = ""
end

# Last come first shown
function merge_helpinfo(base::HelpInfo, overlay::HelpInfo)
    return HelpInfo(
        hidden = base.hidden || overlay.hidden,
        brief = isempty(overlay.brief) ? base.brief : overlay.brief,
        description = isempty(overlay.description) ? base.description : overlay.description,
        footer = isempty(overlay.footer) ? base.footer : overlay.footer,
    )
end

@inline ishidden(info::HelpInfo) = info.hidden

# The help information decides if a node is hidden or not, and it does it
# by wrapping the node usage node in an Hidden Usage node.
@inline _usage_or_hidden(info::HelpInfo, node::UsageNode) =
    info.hidden ? UsageHidden(node) : node


# HelpInfo will be used to populate the HelpDoc
# The HelpDoc is a structure holding information about the scope, that is, "who asked for help"
# and all the information needed to generate help messages.
# The focused usage is what will give us the exact scope of the help document to be rendered.
# Additionally, it will have all the information provided by the HelpInfo for that currently scoped node.
# Lastly, it will hold an optionally empty list of Help Entries to list any additional information
# if the node has children
# The help entry is basically the same shape as the HelpDoc, but we need to keep them separate because
# What we do with them and how we render them is different

struct HelpEntry
    usage::UsageNode
    info::HelpInfo
end

# The usage node should provide all the information about what entry is that, what names or metavariables
# does it use, The helpinfo holds all the information about what it is and how it is described.
# There will be a lot of redundant information for most render modes.

struct HelpDoc
    prefix::Vector{String}
    usage::UsageNode
    info::HelpInfo
    entries::Vector{HelpEntry}
end

# how do we build our helpdoc?
# - upon request or when needed We will reconstruct our position in the parser tree using the list of arguments.
# - From there we will return the context after we finish parsing either due to an error or due to exhausting the tokens
# in the input buffer.
# - This context will then be used by a function like "focused_helpdoc(p::AbstractParser, ctx::Context, rt::Runtime)"
# - the function will then begin descending the tree again, unpacking the context as it goes and gathering information
# from the overlays on the nodes.
# - The function does not know how to handle all types of states and contexts, instead it will delegate to each parser to go through with the focusing
# based on the contetxt

# The runtime is still to be properly designed. The Initial approach was to use ScopedValues but they are not yet trim
# friendly. So the new approach is to just pass through a collection of context information.
# One design decision is whether to have the overlay propagate to the children or simply live for the immediate node they wrap and that's it.
# It can be done by having normal nodes propagate a default runtime, and only help overlay nodes update and passing a
# filled runtime to the wrapped node.
