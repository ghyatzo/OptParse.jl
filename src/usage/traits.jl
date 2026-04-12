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
    elseif (node.kind == USAGE_Alternative
        || node.kind == USAGE_Object
        || node.kind == USAGE_Tuple)
        return _tuple_renders_empty(node.children)
    elseif (node.kind == USAGE_Optional
        || node.kind == USAGE_Repeat)
        return _usage_renders_empty(first(node.children))
    else
        return false
    end

end

function _tuple_renders_empty(nodes::Vector{UsageNode})
    isempty(nodes) && return true
    all(_usage_renders_empty(node) for node in nodes)
end

function _tuple_nvisible(nodes::Vector{UsageNode})
    isempty(nodes) && return 0
    count(_usage_renders_empty, nodes)
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
    if (node.kind == USAGE_Flag
        || node.kind == USAGE_Option)
        return true
    elseif (node.kind == USAGE_Optional
        || node.kind == USAGE_Repeat
        || node.kind == USAGE_Hidden)
        return _usage_is_optionlike(first(node.children))
    else
        return false
    end
end

function _tuple_ncompact_segments(nodes::UsageNode)
    isempty(nodes) && return 0

    compact_segments = 0
    for node in nodes
        _usage_renders_empty(node) && continue
        _usage_should_collapse_optional_option(node) && (compact_segments += 1)
    end
end



##=---------------------=##
#   grouping / layouts
##=---------------------=##

function _usage_needs_grouping(node::UsageNode)
    return (node.kind == USAGE_Object || node.kind == USAGE_Tuple) ?
        _tuple_has_multiple_visible(node.children) : false
end

