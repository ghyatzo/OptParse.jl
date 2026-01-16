# we want to create an usage tree, that then can be traversed and formatted accordingly to generate
# a human readable usage string.

# single type approach
struct Term
    type::Symbol
    names::Vector{String}
    meta::String
    terms::Vector{Vector{Term}}
end

const Usage = Vector{Term}

flagterm(names::Vector{String}) = Term(:FLAG, names, "", Usage[])
optionterm(meta::String, names::Vector{String}) = Term(:OPTION, names, meta, Usage[])
argterm(meta::String) = Term(:ARG, String[], meta, Usage[])
cmdterm(names::Vector{String}, usage::Usage) = Term(:CMD, names, "", [usage])

multiterm(usage::Usage) = Term(:MULTI, String[], "", [usage])
optionalterm(usage::Usage) = Term(:OPTIONAL, String[], "", [usage])
exclusiveterm(usages::Vector{Usage}) = Term(:OR, String[], "", usages)

function format_usage(usage::Usage)
    s = " "
    for term in usage

        if term.type == :OR
            s *= join(map(format_usage, term.terms), '\n')
        elseif term.type == :OPTIONAL
            s *= "[$(format_usage(term.terms[1]))]"
        elseif term.type == :MULTI
            s *= format_usage(term.terms[1])z
        elseif term.type == :CMD
            s *= "$(term.names[1]) $(format_usage(term.terms[1]))"
        elseif term.type == :ARG
            s *= "<$(uppercase(term.meta))>"
        elseif term.type == :OPTION
            names = length(term.names) == 1 ? "$(term.names[1])" : "($(join(term.names, '/')))"
            s *= "$names=<$(uppercase(term.meta))>"
        elseif term.type == :FLAG
            names = length(term.names) == 1 ? "$(term.names[1])" : "($(join(term.names, '/')))"
            s *= "$names"
        end
    end

    return s
end


# @wrapped struct _UsageTerm{U}
#     union::U
# end

# struct FlagUsage
#     names::Vector{String}
# end

# struct OptionUsage
#     meta::String
#     names::Vector{String}
# end

# struct ArgumentUsage
#     meta::String
# end

# struct CommandUsage
#     names::Vector{String}
# end

# struct MultiUsage
#     terms::Vector{_UsageTerm}
# end

# struct OptionalUsage
#     terms::Vector{_UsageTerm}
# end

# struct ExclusiveUsage
#     terms::Vector{Vector{_UsageTerm}}
# end

# const UsageTerm = _UsageTerm{
#     Union{
#         FlagUsage,
#         OptionUsage,
#         ArgumentUsage,
#         CommandUsage,
#         MultiUsage,
#         OptionalUsage,
#         ExclusiveUsage,
#     },
# }
