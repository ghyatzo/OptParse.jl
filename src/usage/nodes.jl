@enum UsageKind::UInt8 begin
    USAGE_Flag
    USAGE_Option
    USAGE_Argument
    USAGE_Command
    USAGE_Object
    USAGE_Tuple
    USAGE_Alternative
    USAGE_Optional
    USAGE_Repeat
    USAGE_Hidden
    USAGE_Empty
end

@kwdef struct UsageNode
    kind::UsageKind = USAGE_Empty
    names::Vector{String} = String[]
    metavar::String = ""
    children::Vector{UsageNode} = UsageNode[]
    min::Int = 0
    max::Int = 0
end

UsageFlag(names::Vector{String}) =
    UsageNode(kind = USAGE_Flag, names = names)
UsageFlag(names::Tuple{Vararg{String}}) = UsageFlag(String[name for name in names])
UsageFlag(names::Vararg{String}) = UsageFlag(String[name for name in names])


UsageOption(names::Vector{String}, metavar::AbstractString) =
    UsageNode(kind = USAGE_Option, names = names, metavar = String(metavar))
UsageOption(names::Tuple{Vararg{String}}, metavar::AbstractString) =
    UsageOption(String[name for name in names], String(metavar))


UsageArgument(metavar::AbstractString) =
    UsageNode(kind = USAGE_Argument, metavar = String(metavar))


UsageCommand(names::Vector{String}, child::UsageNode) =
    UsageNode(kind = USAGE_Command, names = names, children = UsageNode[child])
UsageCommand(names::Tuple{Vararg{String}}, child::UsageNode) = UsageCommand(String[name for name in names], child)

UsageObject(items::Vector{UsageNode}) = UsageNode(kind = USAGE_Object, children = items)
UsageObject(items::Tuple{Vararg{UsageNode}}) = UsageObject(UsageNode[item for item in items])
UsageObject(items::Vararg{UsageNode}) = UsageObject(UsageNode[item for item in items])

UsageTuple(items::Vector{UsageNode}) = UsageNode(kind = USAGE_Tuple, children = items)
UsageTuple(items::Tuple{Vararg{UsageNode}}) = UsageTuple(UsageNode[item for item in items])
UsageTuple(items::Vararg{UsageNode}) = UsageTuple(UsageNode[item for item in items])

UsageAlternative(branches::Vector{UsageNode}) =
    UsageNode(kind = USAGE_Alternative, children = branches)
UsageAlternative(branches::Tuple{Vararg{UsageNode}}) = UsageAlternative(UsageNode[b for b in branches])
UsageAlternative(branches::Vararg{UsageNode}) = UsageAlternative(UsageNode[b for b in branches])


UsageOptional(child::UsageNode) = UsageNode(kind = USAGE_Optional, children = UsageNode[child])


UsageRepeat(child::UsageNode, min::Integer, max::Integer) =
    UsageNode(kind = USAGE_Repeat, children = UsageNode[child], min = Int(min), max = Int(max))

UsageHidden(child::UsageNode) = UsageNode(kind = USAGE_Hidden, children = UsageNode[child])

UsageEmpty() = UsageNode()

struct FocusedUsage
    prefix::Vector{String}
    usage::UsageNode
end

FocusedUsage(usage::UsageNode) = FocusedUsage(String[], usage)

function _usage_with_prefix(progname::AbstractString, prefix::Vector{String})
    isempty(prefix) && return String(progname)

    io = IOBuffer()
    wrote = false

    if !isempty(progname)
        print(io, progname)
        wrote = true
    end

    for part in prefix
        wrote && print(io, ' ')
        print(io, part)
        wrote = true
    end

    return String(take!(io))
end

function _usage_push_prefix(prefix::Vector{String}, part::String)
    next = String[]
    sizehint!(next, length(prefix) + 1)
    append!(next, prefix)
    push!(next, part)
    return next
end

@generated function _usage_children(parsers::PTup) where {PTup <: Tuple}
    N = fieldcount(PTup)
    body = Expr(:block)
    for i in 1:N
        push!(body.args, :(children[$i] = usage(parsers[$i])::UsageNode))
    end

    return quote
        children = Vector{UsageNode}(undef, $N)
        $body
        return children
    end
end


abstract type AbstractUsageRenderStyle end

struct UsageCompactStyle <: AbstractUsageRenderStyle end
struct UsageExpandedStyle <: AbstractUsageRenderStyle end

Base.@kwdef struct UsageRenderState
    # Prefix to repeat when a child renderer decides to spill onto later lines.
    continuation_prefix::String = ""
    # Inline subrenders disable multiline to avoid nested stacked layouts inside wrappers.
    allow_multiline::Bool = true
end
