abstract type AbstractUsageNode end

struct UsageFlag{Names <: Tuple{Vararg{String}}} <: AbstractUsageNode
    names::Names
end

struct UsageOption{Names <: Tuple{Vararg{String}}} <: AbstractUsageNode
    names::Names
    metavar::String
end

struct UsageArgument <: AbstractUsageNode
    metavar::String
end

struct UsageCommand{Names <: Tuple{Vararg{String}}, Child} <: AbstractUsageNode
    names::Names
    child::Child
end

struct UsageObject{Items <: Tuple} <: AbstractUsageNode
    items::Items
end

struct UsageTuple{Items <: Tuple} <: AbstractUsageNode
    items::Items
end

struct UsageAlternative{Branches <: Tuple} <: AbstractUsageNode
    branches::Branches
end

struct UsageOptional{Child} <: AbstractUsageNode
    child::Child
end

struct UsageRepeat{Child} <: AbstractUsageNode
    child::Child
    min::Int
    max::Int
end

struct UsageHidden{Child} <: AbstractUsageNode
    child::Child
end

UsageFlag(names::Vararg{String}) = UsageFlag(names)
UsageOption(names::Tuple{Vararg{String}}, metavar::AbstractString) =
    UsageOption{typeof(names)}(names, String(metavar))
UsageOption(metavar::AbstractString, names::Vararg{String}) =
    UsageOption(names, String(metavar))

UsageArgument(metavar::AbstractString) = UsageArgument(String(metavar))
UsageCommand(child, names::Vararg{String}) = UsageCommand(names, child)
UsageObject(items::Vararg{Any}) = UsageObject(items)
UsageTuple(items::Vararg{Any}) = UsageTuple(items)
UsageAlternative(branches::Vararg{Any}) = UsageAlternative(branches)
UsageRepeat(child, min::Integer, max::Integer) = UsageRepeat{typeof(child)}(child, Int(min), Int(max))

abstract type AbstractUsageRenderStyle end

struct UsageCompactStyle <: AbstractUsageRenderStyle end
struct UsageExpandedStyle <: AbstractUsageRenderStyle end

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

    if !isempty(progname)
        print(io, progname)
        _usage_renders_empty(node) || print(io, ' ')
    end

    _render_usage(io, node, resolved_style)
    return nothing
end

_usage_renders_empty(::UsageHidden) = true
_usage_renders_empty(node::UsageOptional) = _usage_renders_empty(node.child)
_usage_renders_empty(node::UsageRepeat) = _usage_renders_empty(node.child)
_usage_renders_empty(node::UsageAlternative) = _tuple_renders_empty(node.branches)
_usage_renders_empty(node::UsageObject) = _tuple_renders_empty(node.items)
_usage_renders_empty(node::UsageTuple) = _tuple_renders_empty(node.items)
_usage_renders_empty(::AbstractUsageNode) = false

_tuple_renders_empty(::Tuple{}) = true
function _tuple_renders_empty(items::Tuple)

    _usage_renders_empty(first(items)) && return _tuple_renders_empty(Base.tail(items))
    return false
end

function _render_usage(io::IO, node::UsageFlag, ::AbstractUsageRenderStyle)
    print(io, _usage_primary_name(node.names))
end

function _render_usage(io::IO, node::UsageOption, ::AbstractUsageRenderStyle)
    print(io, _usage_primary_name(node.names))
    print(io, " <")
    print(io, _usage_metavar(node.metavar))
    print(io, '>')
end

function _render_usage(io::IO, node::UsageArgument, ::AbstractUsageRenderStyle)
    print(io, '<')
    print(io, _usage_metavar(node.metavar))
    print(io, '>')
end

function _render_usage(io::IO, node::UsageCommand, style::AbstractUsageRenderStyle)
    print(io, node.names[1])
    _usage_renders_empty(node.child) && return nothing
    print(io, ' ')
    _render_usage(io, node.child, style)
end

function _render_usage(io::IO, node::UsageObject, style::UsageExpandedStyle)
    _render_usage_tuple(io, node.items, style)
end

function _render_usage(io::IO, node::UsageTuple, style::UsageExpandedStyle)
    _render_usage_tuple(io, node.items, style)
end

function _render_usage(io::IO, node::UsageObject, style::UsageCompactStyle)
    _render_usage_object_compact(io, node.items, style)
end

function _render_usage(io::IO, node::UsageTuple, style::UsageCompactStyle)
    _render_usage_tuple(io, node.items, style)
end

function _render_usage(io::IO, node::UsageAlternative, style::AbstractUsageRenderStyle)
    print(io, '(')
    _render_usage_alternatives(io, node.branches, style)
    print(io, ')')
end

function _render_usage(io::IO, node::UsageOptional, style::AbstractUsageRenderStyle)
    print(io, '[')
    _render_wrapped_usage(io, node.child, style)
    print(io, ']')
end

function _render_usage(io::IO, node::UsageRepeat, style::AbstractUsageRenderStyle)
    _render_repeat(io, node.child, node.min, node.max, style)
end

_render_usage(::IO, ::UsageHidden, ::AbstractUsageRenderStyle) = nothing

_render_usage_tuple(io::IO, items::Tuple, style::AbstractUsageRenderStyle) =
    _render_usage_tuple(io, items, style, true)

_render_usage_tuple(::IO, ::Tuple{}, ::AbstractUsageRenderStyle, ::Bool) = nothing
function _render_usage_tuple(io::IO, items::Tuple, style::AbstractUsageRenderStyle, first_item::Bool)
    head = first(items)
    tail = Base.tail(items)

    if !_usage_renders_empty(head)
        first_item || print(io, ' ')
        _render_usage(io, head, style)
        first_item = false
    end

    _render_usage_tuple(io, tail, style, first_item)
    return nothing
end

function _render_usage_alternatives(io::IO, branches::Tuple, style::AbstractUsageRenderStyle)
    _render_usage(io, first(branches), style)
    _render_usage_alternatives_tail(io, Base.tail(branches), style)
    return nothing
end

_render_usage_alternatives_tail(::IO, ::Tuple{}, ::AbstractUsageRenderStyle) = nothing
function _render_usage_alternatives_tail(io::IO, branches::Tuple, style::AbstractUsageRenderStyle)
    print(io, " | ")
    _render_usage(io, first(branches), style)
    _render_usage_alternatives_tail(io, Base.tail(branches), style)
    return nothing
end

function _render_wrapped_usage(io::IO, node::AbstractUsageNode, style::AbstractUsageRenderStyle)
    if _usage_needs_grouping(node)
        print(io, '(')
        _render_usage(io, node, style)
        print(io, ')')
    else
        _render_usage(io, node, style)
    end
    return nothing
end

function _render_repeat(io::IO, child::AbstractUsageNode, min::Int, max::Int, style::AbstractUsageRenderStyle)
    if max < min
        throw(ArgumentError("UsageRepeat requires max >= min"))
    end

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

_usage_needs_grouping(::UsageAlternative) = true
_usage_needs_grouping(node::UsageObject) = _tuple_has_multiple_visible(node.items)
_usage_needs_grouping(node::UsageTuple) = _tuple_has_multiple_visible(node.items)
_usage_needs_grouping(::AbstractUsageNode) = false

function _render_usage_object_compact(io::IO, items::Tuple, style::UsageCompactStyle)
    if !_tuple_has_optional_optionlike(items)
        _render_usage_tuple(io, items, style)
        return nothing
    end

    first_item = true
    wrote_optional_options = false

    _render_usage_object_compact(io, items, style, first_item, wrote_optional_options)
    return nothing
end

_render_usage_object_compact(::IO, ::Tuple{}, ::UsageCompactStyle, ::Bool, ::Bool) = nothing
function _render_usage_object_compact(io::IO, items::Tuple, style::UsageCompactStyle, first_item::Bool, wrote_optional_options::Bool)
    head = first(items)
    tail = Base.tail(items)

    if _usage_should_collapse_optional_option(head)
        if !wrote_optional_options
            first_item || print(io, ' ')
            print(io, "[OPTIONS]")
            first_item = false
            wrote_optional_options = true
        end
    elseif !_usage_renders_empty(head)
        first_item || print(io, ' ')
        _render_usage(io, head, style)
        first_item = false
    end

    _render_usage_object_compact(io, tail, style, first_item, wrote_optional_options)
    return nothing
end

_tuple_has_optional_optionlike(::Tuple{}) = false
function _tuple_has_optional_optionlike(items::Tuple)
    _usage_should_collapse_optional_option(first(items)) && return true
    return _tuple_has_optional_optionlike(Base.tail(items))
end

_tuple_has_multiple_visible(items::Tuple) = _tuple_nvisible(items) > 1

_tuple_nvisible(::Tuple{}) = 0
function _tuple_nvisible(items::Tuple)
    head = first(items)
    return (_usage_renders_empty(head) ? 0 : 1) + _tuple_nvisible(Base.tail(items))
end

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

function _usage_primary_name(names::Tuple{Vararg{String}})
    for name in names
        startswith(name, "--") && return name
    end

    return names[1]
end

_usage_metavar(metavar::String) = isempty(metavar) ? "VALUE" : metavar
