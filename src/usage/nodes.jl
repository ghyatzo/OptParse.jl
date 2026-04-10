abstract type AbstractUsageNode end


##==------------------==-
#   Flag Node
##==------------------==-


struct UsageFlag{
        Names <: Tuple{Vararg{String}}
    } <: AbstractUsageNode

    names::Names
end

UsageFlag(names::Vararg{String}) = UsageFlag(names)


##==------------------==-
#   Option Node
##==------------------==-

struct UsageOption{
        Names <: Tuple{Vararg{String}}
    } <: AbstractUsageNode

    names::Names
    metavar::String
end

UsageOption(names::Tuple{Vararg{String}}, metavar::AbstractString) =
    UsageOption{typeof(names)}(names, String(metavar))

UsageOption(metavar::AbstractString, names::Vararg{String}) =
    UsageOption(names, String(metavar))


##==------------------==-
#   Argument Node
##==------------------==-


struct UsageArgument <: AbstractUsageNode
    metavar::String
end


UsageArgument(metavar::AbstractString) = UsageArgument(String(metavar))


##==------------------==-
#   Command Node
##==------------------==-

struct UsageCommand{
        Names <: Tuple{Vararg{String}},
        Child <: AbstractUsageNode
    } <: AbstractUsageNode

    names::Names
    child::Child
end

UsageCommand(child::AbstractUsageNode, names::Vararg{String}) = UsageCommand(names, child)



##==------------------==-
#   Object Node
##==------------------==-

struct UsageObject{
        Items <: Tuple{Vararg{AbstractUsageNode}}
    } <: AbstractUsageNode

    items::Items
end


UsageObject(items::Vararg{AbstractUsageNode}) = UsageObject(items)

##==------------------==-
#   Tuple Node
##==------------------==-

struct UsageTuple{
        Items <: Tuple{Vararg{AbstractUsageNode}}
    } <: AbstractUsageNode

    items::Items
end


UsageTuple(items::Vararg{AbstractUsageNode}) = UsageTuple(items)

##==------------------==-
#   Or Node
##==------------------==-

struct UsageAlternative{
        Branches <: Tuple{Vararg{AbstractUsageNode}}
    } <: AbstractUsageNode

    branches::Branches
end

UsageAlternative(branches::Vararg{AbstractUsageNode}) = UsageAlternative(branches)

##==------------------==-
#   Optional Node (default/optional)
##==------------------==-

struct UsageOptional{Child <: AbstractUsageNode} <: AbstractUsageNode
    child::Child
end

##==------------------==-
#   Repeat Node
##==------------------==-

struct UsageRepeat{Child <: AbstractUsageNode} <: AbstractUsageNode
    child::Child
    min::Int
    max::Int
end

UsageRepeat(child::AbstractUsageNode, min::Integer, max::Integer) =
    UsageRepeat{typeof(child)}(child, Int(min), Int(max))

##==------------------==-
#   Hidden Node
##==------------------==-

struct UsageHidden{Child <: AbstractUsageNode} <: AbstractUsageNode
    child::Child
end

struct UsageEmpty <: AbstractUsageNode end

