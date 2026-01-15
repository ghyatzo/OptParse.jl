@wrapped struct _UsageTerm{U}
    union::U
end

struct FlagUsage
    names::Vector{String}
end

struct OptionUsage
    meta::String
    names::Vector{String}
end

struct ArgumentUsage
    meta::String
end

struct CommandUsage
    names::Vector{String}
end

struct MultiUsage
    min::Int
    terms::Vector{_UsageTerm}
end

struct OptionalUsage
    terms::Vector{_UsageTerm}
end

struct ExclusiveUsage
    terms::Vector{_UsageTerm}
end

const UsageTerm = _UsageTerm{
    Union{
        FlagUsage,
        OptionUsage,
        ArgumentUsage,
        CommandUsage,
        MultiUsage,
        OptionalUsage,
        ExclusiveUsage,
    },
}
