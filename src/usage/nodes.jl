
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


UsageFlag(names::Vararg{String}) = UsageNode(kind=USAGE_Flag, names=names)


UsageOption(names::Tuple{Vararg{String}}, metavar::AbstractString) =
    UsageNode(kind = USAGE_Option, names=names, metavar=String(metavar))

UsageOption(metavar::AbstractString, names::Vararg{String}) =
    UsageNode(kind = USAGE_Option, names=names, metavar=String(metavar))


UsageArgument(metavar::AbstractString) =
    UsageNode(kind = USAGE_Argument, metavar=String(metavar))


UsageCommand(child::UsageNode, names::Vararg{String}) =
    UsageNode(kind = USAGE_Command, names=names, children = UsageNode[child])


UsageObject(items::Vararg{UsageNode}) =
    UsageNode(kind = USAGE_Object, children = UsageNode[items...])


UsageTuple(items::Vararg{AbstractUsageNode}) =
    UsageNode(kind = USAGE_Tuple, children = UsageNode[items...])


UsageAlternative(branches::Vararg{AbstractUsageNode}) =
    UsageNode(kind = USAGE_Alternative, children = UsageNode[branches...])


UsageOptional(child::UsageNode) = UsageNode(kind = USAGE_Optional, children = UsageNode[child])


UsageRepeat(child::UsageNode, min::Integer, max::Integer) =
    UsageNode(kind = USAGE_Repeat, children=UsageNode[child], min = Int(min), max=Int(max))

UsageHidden(child::UsageNode) = UsageNode(kind=USAGE_Hidden, children=UsageNode[child])

UsageEmpty() = UsageNode()

