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

function usage(p::ModHelp{T, S, _p, P}) where {T, S, _p, P <: AbstractParser{<:Any, S}}
    child_usage = usage(p.parser)::UsageNode
    return ishidden(p.info) ? UsageHidden(child_usage) : child_usage
end

helpentries(p::ModHelp, rt::OverlayContext) = ishidden(p.info) ? HelpEntry[] :
    @unionsplit helpentries(p.parser, with_helpinfo(rt, p.info))::Vector{HelpEntry}

function focused_helpdoc(
        p::ModHelp{T, S, _p, P},
        ctx::Context{S},
        prefix::Vector{String},
        rt::OverlayContext
    )::HelpDoc where {T, S, _p, P <: AbstractParser{<:Any, S}}
    info = p.info
    info.hidden && return HelpDoc(
        prefix,
        UsageHidden(usage(p.parser)::UsageNode),
        info,
        @unionsplit helpentries(p.parser, with_helpinfo(rt, info))::Vector{HelpEntry}
    )
    return @unionsplit focused_helpdoc(p.parser, ctx, prefix, with_helpinfo(rt, info))::HelpDoc
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
