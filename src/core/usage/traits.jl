abstract type AbstractUsageRenderStyle end

struct UsageCompactStyle <: AbstractUsageRenderStyle end
struct UsageExpandedStyle <: AbstractUsageRenderStyle end

Base.@kwdef struct UsageRenderState
    # Prefix to repeat when a child renderer decides to spill onto later lines.
    continuation_prefix::String = ""
    # Inline subrenders disable multiline to avoid nested stacked layouts inside wrappers.
    allow_multiline::Bool = true
end

##=---------------------=##
#   basic usage traits
##=---------------------=##

_usage_metavar(metavar::String) = isempty(metavar) ? "VALUE" : metavar

function _usage_primary_name(names::Vector{String})
    for name in names
        startswith(name, "--") && return name
    end

    return names[1]
end


function _usage_renders_empty(node::UsageNode)
    if node.kind == USAGE_Hidden || node.kind == USAGE_Empty
        return true
    elseif (
            node.kind == USAGE_Alternative
                || node.kind == USAGE_Object
                || node.kind == USAGE_Tuple
        )
        return _tuple_renders_empty(node.children)
    elseif (
            node.kind == USAGE_Optional
                || node.kind == USAGE_Repeat
        )
        return _usage_renders_empty(first(node.children))
    else
        return false
    end

end

function _tuple_renders_empty(nodes::Vector{UsageNode})
    isempty(nodes) && return true
    return all(_usage_renders_empty(node) for node in nodes)
end

function _tuple_nvisible(nodes::Vector{UsageNode})
    isempty(nodes) && return 0
    return count(!_usage_renders_empty(node) for node in nodes)
end

@inline _tuple_has_multiple_visible(nodes::Vector{UsageNode}) = _tuple_nvisible(nodes) > 1

function _all_visible_are_commands(nodes::Vector{UsageNode})
    isempty(nodes) && return false

    for node in nodes
        _usage_renders_empty(node) && continue
        node.kind != USAGE_Command && return false
    end

    return true
end


##=---------------------=##
#   optional option collapse
##=---------------------=##

_usage_should_collapse_optional_option(node) =
    _usage_is_optional(node) && _usage_is_optionlike(node)

function _usage_is_optional(node::UsageNode)
    node.kind == USAGE_Optional && return true
    node.kind == USAGE_Repeat && node.min == 0 && return true
    return false
end

function _usage_is_optionlike(node::UsageNode)
    if (
            node.kind == USAGE_Flag
                || node.kind == USAGE_Option
        )
        return true
    elseif (
            node.kind == USAGE_Optional
                || node.kind == USAGE_Repeat
                || node.kind == USAGE_Hidden
        )
        return _usage_is_optionlike(first(node.children))
    else
        return false
    end
end

function _tuple_ncompact_segments(nodes::Vector{UsageNode})
    isempty(nodes) && return 0

    compact_segments = 0
    wrote_optional_options = false
    for node in nodes
        _usage_renders_empty(node) && continue
        if _usage_should_collapse_optional_option(node)
            if !wrote_optional_options
                compact_segments += 1
                wrote_optional_options = true
            end
        else
            compact_segments += 1
        end
    end

    return compact_segments
end


##=---------------------=##
#   grouping / layouts
##=---------------------=##

function _usage_needs_grouping(node::UsageNode)
    return (node.kind == USAGE_Object || node.kind == USAGE_Tuple) ?
        _tuple_has_multiple_visible(node.children) : false
end

@inline function _usage_alternative_layout(branches::Vector{UsageNode}, state::UsageRenderState)
    # Command-only alternatives are summarized structurally instead of spelling
    # out every subcommand in compact usage.
    if _all_visible_are_commands(branches)
        return :commands
    end

    nvisible = _tuple_nvisible(branches)
    if nvisible <= 2
        return :inline
    end

    return state.allow_multiline ? :stacked : :inline_elided
end
