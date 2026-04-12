
UsageStyle(::Val{:compact}) = UsageCompactStyle()
UsageStyle(::Val{:expanded}) = UsageExpandedStyle()
UsageStyle(style::Symbol) =
    style === :compact ? UsageCompactStyle() :
    style === :expanded ? UsageExpandedStyle() :
    throw(ArgumentError("Unknown usage render style: $(style)"))

function render_usage(node::UsageNode; style::Symbol = :compact, progname::AbstractString = "")
    io = IOBuffer()
    render_usage(io, node; style, progname)
    return String(take!(io))
end

function render_usage(io::IO, node::UsageNode; style::Symbol = :compact, progname::AbstractString = "")
    resolved_style = UsageStyle(style)
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

function _render_usage_inline_string(node::UsageNode, style::AbstractUsageRenderStyle)
    io = IOBuffer()
    # Inline renders intentionally forbid multiline so wrappers such as `[ ... ]`
    # and parenthesized groups stay on one logical segment.
    _render_usage(io, node, style, UsageRenderState(allow_multiline = false))
    return String(take!(io))
end

function _render_wrapped_usage(io::IO, node::UsageNode, style::AbstractUsageRenderStyle)
    if _usage_needs_grouping(node)
        print(io, '(')
        print(io, _render_usage_inline_string(node, style))
        print(io, ')')
    else
        print(io, _render_usage_inline_string(node, style))
    end
    return nothing
end




function _render_usage(io::IO, node::UsageNode, style::AbstractUsageRenderStyle, state::UsageRenderState)

    ##=----------------------------=##
    #   leaf rendering
    ##=----------------------------=##
    if node.kind == USAGE_Flag
        print(io, _usage_primary_name(node.names))
    elseif node.kind == USAGE_Option
        print(io, _usage_primary_name(node.names))
        print(io, " <")
        print(io, _usage_metavar(node.metavar))
        print(io, '>')
    elseif node.kind == USAGE_Argument
        print(io, '<')
        print(io, _usage_metavar(node.metavar))
        print(io, '>')

    elseif node.kind == USAGE_Command
        cmdname = first(node.names)
        childnode = first(node.children)
        print(io, cmdname)
        _usage_renders_empty(childnode) && return nothing
        print(io, ' ')
        # Once a command token has been emitted, continuations inside the command
        # branch should repeat that already-rendered command path.
        child_state = _usage_continue_with(state, cmdname * " ")
        _render_usage(io, childnode, style, child_state)


    elseif node.kind == USAGE_Object && style isa UsageCompactStyle
        _render_usage_object_compact(io, node.children, style, state)
    elseif (node.kind == USAGE_Object || node.kind == USAGE_Tuple)
        _render_usage_sequence(io, node.children, style, state)
    elseif node.kind == USAGE_Alternative

        layout = _usage_alternative_layout(node.children, state)

        if layout === :commands
            print(io, "<COMMAND> [ARGS...]")
        elseif layout === :stacked
            _render_usage_alternatives_stacked(io, node.children, style, state)
        elseif layout === :inline_elided
            _render_usage_alternatives_inline(io, node.children, style, true)
        else
            _render_usage_alternatives_inline(io, node.children, style, false)
        end
    elseif node.kind == USAGE_Optional
        print(io, '[')
        _render_wrapped_usage(io, first(node.children), style)
        print(io, ']')
    elseif node.kind == USAGE_Repeat
        min = node.min
        max = node.max
        childnode = first(node.children)
        max < min && throw(ArgumentError("UsageRepeat requires max >= min"))


        if min == 0 && max == 1
            print(io, '[')
            _render_wrapped_usage(io, childnode, style)
            print(io, ']')
            return nothing
        end

        if max == typemax(Int)
            if min == 0
                print(io, '[')
                _render_wrapped_usage(io, childnode, style)
                print(io, "]...")
            elseif min == 1
                _render_wrapped_usage(io, childnode, style)
                print(io, "...")
            end

            return nothing
        end

        _render_repeat_items(io, childnode, min, max, style)
    else
        return nothing
    end

    return nothing
end


##=----------------------------=##
#   sequence / product rendering
##=----------------------------=##
function _render_usage_sequence(
    io::IO,
    nodes::Vector{UsageNode},
    style::AbstractUsageRenderStyle,
    state::UsageRenderState,
    nvisible = _tuple_nvisible(nodes)
)

    iszero(nvisible) && return nothing

    curr_visible = nvisible
    curr_state = state
    for node in nodes
        _usage_renders_empty(node) && continue

        if curr_visible == 1
            _render_usage(io, node, style, curr_state)
            return nothing
        end

        chunk = _render_usage_inline_string(node, style)
        if !isempty(chunk)
            print(io, chunk)
            print(io, ' ')

            curr_state = _usage_continue_with(curr_state, chunk * " ")
            curr_visible -= 1
        end
    end

    return nothing
end


##=----------------------------=##
#   compact object rendering
##=----------------------------=##

function _render_usage_object_compact(
    io::IO,
    nodes::Vector{UsageNode},
    style::UsageCompactStyle,
    state::UsageRenderState,
    nsegments = _tuple_ncompact_segments(nodes)
)
    iszero(nsegments) && return nothing

    curr_state = state
    wrote_optional_options = false
    for node in nodes
        _usage_renders_empty(node) && continue

        if _usage_should_collapse_optional_option(node)
            wrote_optional_options && continue

            if nsegments == 1
                print(io, "[OPTIONS]")
                return nothing
            end

            # Compact object rendering coalesces any number of optional option-like
            # entries into a single `[OPTIONS]` segment.

            print(io, "[OPTIONS] ")
            curr_state = _usage_continue_with(curr_state, "[OPTIONS] ")
            nsegments -= 1
            wrote_optional_options = true
            continue
        end

        if nsegments == 1
            _render_usage(io, node, style, curr_state)
            return nothing
        end

        chunk = _render_usage_inline_string(node, style)
        print(io, chunk)
        print(io, ' ')

        curr_state = _usage_continue_with(curr_state, chunk * " ")
        nsegments -= 1
    end

    return nothing
end








##=----------------------------=##
#   alternative rendering
##=----------------------------=##

function _render_usage_alternatives_inline(
    io::IO,
    nodes::Vector{UsageNode},
    style::AbstractUsageRenderStyle,
    elide::Bool,
    rendered = 0
)
    isempty(nodes) && return nothing

    print(io, '(')

    for (i, node) in enumerate(nodes)
        rendered >= 2 && break
        _usage_renders_empty(node) && continue

        rendered > 0 && print(io, " | ")
        print(io, _render_usage_inline_string(node, style))
        rendered += 1

        if elide && rendered >= 2 && _tuple_nvisible(nodes[i:end]) > 1
            print(io, " | ...")
            break
        end
    end

    print(io, ')')
    return nothing
end


function _render_usage_alternatives_stacked(
    io::IO,
    nodes::Vector{UsageNode},
    style::AbstractUsageRenderStyle,
    state::UsageRenderState,
    rendered = 0
)
    isempty(nodes) && return nothing

    for node in nodes
        rendered >= 2 && break
        _usage_renders_empty(node) && continue

        if rendered > 0
            print(io, '\n')
            print(io, state.continuation_prefix)
        end

        _render_usage(io, node, style, state)
        rendered += 1
    end


    # Keep compact stacked alternatives bounded: two concrete lines plus one
    # ellipsis line if more branches remain.
    if _tuple_nvisible(nodes) > 2
        print(io, '\n')
        print(io, state.continuation_prefix)
        print(io, "...")
    end

    return nothing
end





##=----------------------------=##
#   repeated
##=----------------------------=##


function _render_repeat_items(io::IO, child::UsageNode, min::Int, max::Int, style::AbstractUsageRenderStyle)
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
