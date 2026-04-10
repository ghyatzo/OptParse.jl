
abstract type AbstractUsageRenderStyle end

struct UsageCompactStyle <: AbstractUsageRenderStyle end
struct UsageExpandedStyle <: AbstractUsageRenderStyle end

Base.@kwdef struct UsageRenderState
    # Prefix to repeat when a child renderer decides to spill onto later lines.
    continuation_prefix::String = ""
    # Inline subrenders disable multiline to avoid nested stacked layouts inside wrappers.
    allow_multiline::Bool = true
end

_usage_style(::UsageCompactStyle) = UsageCompactStyle()
_usage_style(::UsageExpandedStyle) = UsageExpandedStyle()
_usage_style(::Val{:compact}) = UsageCompactStyle()
_usage_style(::Val{:expanded}) = UsageExpandedStyle()
_usage_style(style::Symbol) =
    style === :compact ? UsageCompactStyle() :
    style === :expanded ? UsageExpandedStyle() :
    throw(ArgumentError("Unknown usage render style: $(style)"))

function render_usage(node::AbstractUsageNode; style::Union{Symbol, Val, AbstractUsageRenderStyle} = :compact, progname::AbstractString = "")
    io = IOBuffer()
    render_usage(io, node; style, progname)
    return String(take!(io))
end

function render_usage(io::IO, node::AbstractUsageNode; style::Union{Symbol, Val, AbstractUsageRenderStyle} = :compact, progname::AbstractString = "")
    resolved_style = _usage_style(style)
    state = UsageRenderState()

    if !isempty(progname)
        print(io, progname)
        if !_usage_renders_empty(node)
            print(io, ' ')
            state = UsageRenderState(continuation_prefix = progname * " ")
        else
            state = UsageRenderState(continuation_prefix = progname)
        end
    end

    _render_usage(io, node, resolved_style, state)
    return nothing
end

@inline _usage_continue_with(state::UsageRenderState, suffix::AbstractString) =
    UsageRenderState(
        continuation_prefix = state.continuation_prefix * suffix,
        allow_multiline = state.allow_multiline,
    )

function _render_usage_inline_string(node::AbstractUsageNode, style::AbstractUsageRenderStyle)
    io = IOBuffer()
    # Inline renders intentionally forbid multiline so wrappers such as `[ ... ]`
    # and parenthesized groups stay on one logical segment.
    _render_usage(io, node, style, UsageRenderState(allow_multiline = false))
    return String(take!(io))
end

function _render_wrapped_usage(io::IO, node::AbstractUsageNode, style::AbstractUsageRenderStyle)
    if _usage_needs_grouping(node)
        print(io, '(')
        print(io, _render_usage_inline_string(node, style))
        print(io, ')')
    else
        print(io, _render_usage_inline_string(node, style))
    end
    return nothing
end









##=----------------------------=##
#   leaf rendering
##=----------------------------=##

function _render_usage(io::IO, node::UsageFlag, ::AbstractUsageRenderStyle, ::UsageRenderState)
    print(io, _usage_primary_name(node.names))
end

function _render_usage(io::IO, node::UsageOption, ::AbstractUsageRenderStyle, ::UsageRenderState)
    print(io, _usage_primary_name(node.names))
    print(io, " <")
    print(io, _usage_metavar(node.metavar))
    print(io, '>')
end

function _render_usage(io::IO, node::UsageArgument, ::AbstractUsageRenderStyle, ::UsageRenderState)
    print(io, '<')
    print(io, _usage_metavar(node.metavar))
    print(io, '>')
end

_render_usage(::IO, ::UsageHidden, ::AbstractUsageRenderStyle, ::UsageRenderState) = nothing

function _render_usage(io::IO, node::UsageCommand, style::AbstractUsageRenderStyle, state::UsageRenderState)
    print(io, node.names[1])
    _usage_renders_empty(node.child) && return nothing
    print(io, ' ')

    # Once a command token has been emitted, continuations inside the command
    # branch should repeat that already-rendered command path.
    child_state = _usage_continue_with(state, node.names[1] * " ")
    _render_usage(io, node.child, style, child_state)
    return nothing
end












##=----------------------------=##
#   sequence / product rendering
##=----------------------------=##

function _render_usage(io::IO, node::UsageTuple, style::AbstractUsageRenderStyle, state::UsageRenderState)
    _render_usage_sequence(io, node.items, style, state)
end

function _render_usage(io::IO, node::UsageObject, style::UsageExpandedStyle, state::UsageRenderState)
    _render_usage_sequence(io, node.items, style, state)
end

_render_usage_sequence(io::IO, items::Tuple, style::AbstractUsageRenderStyle, state::UsageRenderState) =
    _render_usage_sequence(io, items, style, state, _tuple_nvisible(items))

_render_usage_sequence(::IO, ::Tuple{}, ::AbstractUsageRenderStyle, ::UsageRenderState, ::Int) = nothing
function _render_usage_sequence(io::IO, items::Tuple, style::AbstractUsageRenderStyle, state::UsageRenderState, nvisible::Int)
    nvisible == 0 && return nothing

    head = first(items)
    tail = Base.tail(items)

    if _usage_renders_empty(head)
        return _render_usage_sequence(io, tail, style, state, nvisible)
    end

    if nvisible == 1
        _render_usage(io, head, style, state)
        return nothing
    end

    # All but the final visible segment are rendered inline first. This lets us
    # extend the continuation prefix with the exact text already emitted, so a
    # later multiline child can repeat the full left-hand context verbatim.
    chunk = _render_usage_inline_string(head, style)
    if !isempty(chunk)
        print(io, chunk)
        print(io, ' ')

        next_state = _usage_continue_with(state, chunk * " ")
        _render_usage_sequence(io, tail, style, next_state, nvisible - 1)
    end

    return nothing
end









##=----------------------------=##
#   compact object rendering
##=----------------------------=##

function _render_usage(io::IO, node::UsageObject, style::UsageCompactStyle, state::UsageRenderState)
    _render_usage_object_compact(io, node.items, style, state)
end

_render_usage_object_compact(io::IO, items::Tuple, style::UsageCompactStyle, state::UsageRenderState) =
    _render_usage_object_compact(io, items, style, state, false, _tuple_ncompact_segments(items))

_render_usage_object_compact(::IO, ::Tuple{}, ::UsageCompactStyle, ::UsageRenderState, ::Bool, ::Int) = nothing
function _render_usage_object_compact(io::IO, items::Tuple, style::UsageCompactStyle, state::UsageRenderState, wrote_optional_options::Bool, nsegments::Int)
    nsegments == 0 && return nothing

    head = first(items)
    tail = Base.tail(items)

    if _usage_should_collapse_optional_option(head)
        if wrote_optional_options
            return _render_usage_object_compact(io, tail, style, state, true, nsegments)
        end

        if nsegments == 1
            print(io, "[OPTIONS]")
            return nothing
        end

        # Compact object rendering coalesces any number of optional option-like
        # entries into a single `[OPTIONS]` segment.
        print(io, "[OPTIONS] ")
        next_state = _usage_continue_with(state, "[OPTIONS] ")
        return _render_usage_object_compact(io, tail, style, next_state, true, nsegments - 1)
    end

    if _usage_renders_empty(head)
        return _render_usage_object_compact(io, tail, style, state, wrote_optional_options, nsegments)
    end

    if nsegments == 1
        _render_usage(io, head, style, state)
        return nothing
    end

    chunk = _render_usage_inline_string(head, style)
    print(io, chunk)
    print(io, ' ')

    next_state = _usage_continue_with(state, chunk * " ")
    return _render_usage_object_compact(io, tail, style, next_state, wrote_optional_options, nsegments - 1)
end











##=----------------------------=##
#   alternative rendering
##=----------------------------=##

function _render_usage(io::IO, node::UsageAlternative, style::AbstractUsageRenderStyle, state::UsageRenderState)
    layout = _usage_alternative_layout(node.branches, state)

    if layout === :commands
        print(io, "<COMMAND> [ARGS...]")
    elseif layout === :stacked
        _render_usage_alternatives_stacked(io, node.branches, style, state)
    elseif layout === :inline_elided
        _render_usage_alternatives_inline(io, node.branches, style, true)
    else
        _render_usage_alternatives_inline(io, node.branches, style, false)
    end

    return nothing
end

function _render_usage_alternatives_inline(io::IO, branches::Tuple, style::AbstractUsageRenderStyle, elide::Bool)
    print(io, '(')
    _render_usage_alternatives_inline(io, branches, style, 0, elide)
    print(io, ')')
    return nothing
end

_render_usage_alternatives_inline(::IO, ::Tuple{}, ::AbstractUsageRenderStyle, ::Int, ::Bool) = nothing
function _render_usage_alternatives_inline(io::IO, branches::Tuple, style::AbstractUsageRenderStyle, rendered::Int, elide::Bool)
    rendered >= 2 && return nothing

    head = first(branches)
    tail = Base.tail(branches)

    if _usage_renders_empty(head)
        return _render_usage_alternatives_inline(io, tail, style, rendered, elide)
    end

    rendered > 0 && print(io, " | ")
    print(io, _render_usage_inline_string(head, style))
    rendered += 1

    if elide && rendered >= 2 && _tuple_nvisible(tail) > 0
        print(io, " | ...")
        return nothing
    end

    return _render_usage_alternatives_inline(io, tail, style, rendered, elide)
end

function _render_usage_alternatives_stacked(io::IO, branches::Tuple, style::AbstractUsageRenderStyle, state::UsageRenderState)
    _render_usage_alternatives_stacked(io, branches, style, state, 0)

    # Keep compact stacked alternatives bounded: two concrete lines plus one
    # ellipsis line if more branches remain.
    if _tuple_nvisible(branches) > 2
        print(io, '\n')
        print(io, state.continuation_prefix)
        print(io, "...")
    end

    return nothing
end

_render_usage_alternatives_stacked(::IO, ::Tuple{}, ::AbstractUsageRenderStyle, ::UsageRenderState, ::Int) = nothing
function _render_usage_alternatives_stacked(io::IO, branches::Tuple, style::AbstractUsageRenderStyle, state::UsageRenderState, rendered::Int)
    rendered >= 2 && return nothing

    head = first(branches)
    tail = Base.tail(branches)

    if _usage_renders_empty(head)
        return _render_usage_alternatives_stacked(io, tail, style, state, rendered)
    end

    if rendered > 0
        print(io, '\n')
        print(io, state.continuation_prefix)
    end

    _render_usage(io, head, style, state)
    return _render_usage_alternatives_stacked(io, tail, style, state, rendered + 1)
end













##=----------------------------=##
#   wrappers
##=----------------------------=##

function _render_usage(io::IO, node::UsageOptional, style::AbstractUsageRenderStyle, ::UsageRenderState)
    print(io, '[')
    _render_wrapped_usage(io, node.child, style)
    print(io, ']')
    return nothing
end

function _render_usage(io::IO, node::UsageRepeat, style::AbstractUsageRenderStyle, ::UsageRenderState)
    _render_repeat(io, node.child, node.min, node.max, style)
end

function _render_repeat(io::IO, child::AbstractUsageNode, min::Int, max::Int, style::AbstractUsageRenderStyle)
    max < min && throw(ArgumentError("UsageRepeat requires max >= min"))

    if min == 0 && max == 1
        print(io, '[')
        _render_wrapped_usage(io, child, style)
        print(io, ']')
        return nothing
    end

    if max == typemax(Int)
        if min == 0
            print(io, '[')
            _render_wrapped_usage(io, child, style)
            print(io, "]...")
            return nothing
        elseif min == 1
            _render_wrapped_usage(io, child, style)
            print(io, "...")
            return nothing
        end
    end

    _render_repeat_items(io, child, min, max, style)
    return nothing
end

function _render_repeat_items(io::IO, child::AbstractUsageNode, min::Int, max::Int, style::AbstractUsageRenderStyle)
    first_item = true

    for _ in 1:min
        first_item || print(io, ' ')
        _render_wrapped_usage(io, child, style)
        first_item = false
    end

    if max == typemax(Int)
        first_item || print(io, ' ')
        _render_wrapped_usage(io, child, style)
        print(io, "...")
        return nothing
    end

    for _ in (min + 1):max
        first_item || print(io, ' ')
        print(io, '[')
        _render_wrapped_usage(io, child, style)
        print(io, ']')
        first_item = false
    end

    return nothing
end
