struct ModHelp{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    parser::P
    info::HelpInfo
end

ModHelp(parser::P, info::HelpInfo) where {P <: AbstractParser} =
    ModHelp{
        tval(P),
        tstate(P),
        priority(P),
        P,
    }(parser.initialState, parser, info)

ModHelp(parser::ModHelp, info::HelpInfo) =
    ModHelp(parser.parser, merge_helpinfo(parser.info, info))

helpinfo(p::ModHelp{T, S, _p, P}) where {T, S, _p, P <: AbstractParser{<:Any, S}} =
    merge_helpinfo(helpinfo(p.parser), p.info)

function usage(p::ModHelp{T, S, _p, P}) where {T, S, _p, P <: AbstractParser{<:Any, S}}
    child_usage = usage(p.parser)::UsageNode
    return _usage_or_hidden(helpinfo(p), child_usage)
end

function focused_usage(
        p::ModHelp{T, S, _p, P},
        ctx::Context{S},
        prefix::Vector{String}
    )::FocusedUsage where {T, S, _p, P <: AbstractParser{<:Any, S}}
    info = helpinfo(p)
    info.hidden && return FocusedUsage(prefix, UsageHidden(usage(p.parser)::UsageNode))

    return focused_usage(p.parser, ctx, prefix)
end

@inline function parse(
        p::ModHelp{T, S, _p, P},
        ctx::Context{S}
    )::InnerParseResult{S} where {T, S, _p, P <: AbstractParser{<:Any, S}}
    return @unionsplit parse(p.parser, ctx)::InnerParseResult{S}
end

@inline function complete(
        p::ModHelp{T, S, _p, P},
        st::S
    )::ParseResult{T} where {T, S, _p, P <: AbstractParser{<:Any, S}}
    return @unionsplit complete(p.parser, st)::ParseResult{T}
end
