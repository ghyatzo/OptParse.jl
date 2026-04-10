##=---------------------=##
#   basic usage traits
##=---------------------=##

_usage_metavar(metavar::String) = isempty(metavar) ? "VALUE" : metavar

function _usage_primary_name(names::Tuple{Vararg{String}})
    for name in names
        startswith(name, "--") && return name
    end

    return names[1]
end

_usage_renders_empty(::UsageHidden) = true
_usage_renders_empty(::UsageEmpty) = true
_usage_renders_empty(node::UsageOptional) = _usage_renders_empty(node.child)
_usage_renders_empty(node::UsageRepeat) = _usage_renders_empty(node.child)
_usage_renders_empty(node::UsageAlternative) = _tuple_renders_empty(node.branches)
_usage_renders_empty(node::UsageObject) = _tuple_renders_empty(node.items)
_usage_renders_empty(node::UsageTuple) = _tuple_renders_empty(node.items)
_usage_renders_empty(::AbstractUsageNode) = false

_tuple_renders_empty(::Tuple{}) = true
function _tuple_renders_empty(items::Tuple)
    head = first(items)
    return _usage_renders_empty(head) && _tuple_renders_empty(Base.tail(items))
end

@inline _tuple_nvisible(::Tuple{}) = 0
@inline function _tuple_nvisible(items::Tuple)
    head = first(items)
    return (_usage_renders_empty(head) ? 0 : 1) + _tuple_nvisible(Base.tail(items))
end

@inline _tuple_has_multiple_visible(items::Tuple) = _tuple_nvisible(items) > 1

@inline _tuple_all_visible_are_commands(items::Tuple) = _tuple_all_visible_are_commands(items, false)
@inline _tuple_all_visible_are_commands(::Tuple{}, saw_visible::Bool) = saw_visible
@inline function _tuple_all_visible_are_commands(items::Tuple, saw_visible::Bool)
    head = first(items)

    if _usage_renders_empty(head)
        return _tuple_all_visible_are_commands(Base.tail(items), saw_visible)
    elseif head isa UsageCommand
        return _tuple_all_visible_are_commands(Base.tail(items), true)
    else
        return false
    end
end






##=---------------------=##
#   optional option collapse
##=---------------------=##

_usage_should_collapse_optional_option(node) = _usage_is_optional(node) && _usage_is_optionlike(node)

_usage_is_optional(::UsageOptional) = true
_usage_is_optional(node::UsageRepeat) = node.min == 0
_usage_is_optional(::AbstractUsageNode) = false

_usage_is_optionlike(::UsageFlag) = true
_usage_is_optionlike(::UsageOption) = true
_usage_is_optionlike(node::UsageOptional) = _usage_is_optionlike(node.child)
_usage_is_optionlike(node::UsageRepeat) = _usage_is_optionlike(node.child)
_usage_is_optionlike(node::UsageHidden) = _usage_is_optionlike(node.child)
_usage_is_optionlike(::AbstractUsageNode) = false

@inline _tuple_ncompact_segments(items::Tuple) = _tuple_ncompact_segments(items, false)
@inline _tuple_ncompact_segments(::Tuple{}, ::Bool) = 0
@inline function _tuple_ncompact_segments(items::Tuple, wrote_optional_options::Bool)
    head = first(items)
    tail = Base.tail(items)

    if _usage_should_collapse_optional_option(head)
        return wrote_optional_options ?
            _tuple_ncompact_segments(tail, true) :
            1 + _tuple_ncompact_segments(tail, true)
    elseif _usage_renders_empty(head)
        return _tuple_ncompact_segments(tail, wrote_optional_options)
    else
        return 1 + _tuple_ncompact_segments(tail, wrote_optional_options)
    end
end






##=---------------------=##
#   grouping / layouts
##=---------------------=##

_usage_needs_grouping(::UsageAlternative) = false
_usage_needs_grouping(node::UsageObject) = _tuple_has_multiple_visible(node.items)
_usage_needs_grouping(node::UsageTuple) = _tuple_has_multiple_visible(node.items)
_usage_needs_grouping(::AbstractUsageNode) = false

@inline function _usage_alternative_layout(branches::Tuple, state::UsageRenderState)
    # Command-only alternatives are summarized structurally instead of spelling
    # out every subcommand in compact usage.
    if _tuple_all_visible_are_commands(branches)
        return :commands
    end

    nvisible = _tuple_nvisible(branches)
    if nvisible <= 2
        return :inline
    end

    return state.allow_multiline ? :stacked : :inline_elided
end
