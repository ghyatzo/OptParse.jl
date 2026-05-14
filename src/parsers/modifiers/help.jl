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

@autospecialize p function usage(p::ModHelp{T, S, _p, P}) where {T, S, _p, P <: AbstractParser{T, S}}
    child_usage = usage(p.parser)::UsageNode
    return ishidden(p.info) ? UsageHidden(child_usage) : child_usage
end

@autospecialize p function helpentries(p::ModHelp{T, S, _p, P}, rt::OverlayContext) where {T, S, _p, P <: AbstractParser{T, S}}
    parser = p.parser::P
    return ishidden(p.info) ? HelpEntry[] :
        helpentries(parser, with_helpinfo(rt, p.info))::Vector{HelpEntry}
end

@autospecialize p ctx function focused_helpdoc(
        p::ModHelp{T, S, _p, P},
        ctx::Context{S},
        prefix::Vector{String},
        rt::OverlayContext
    )::HelpDoc where {T, S, _p, P <: AbstractParser{T, S}}
    info = p.info
    parser = p.parser::P
    info.hidden && return HelpDoc(
        prefix,
        UsageHidden(usage(p.parser)::UsageNode),
        info,
        helpentries(parser, with_helpinfo(rt, info))::Vector{HelpEntry}
    )
    return focused_helpdoc(parser, ctx, prefix, with_helpinfo(rt, info))::HelpDoc
end

@autospecialize p ctx function parse(
        p::ModHelp{T, S, _p, P},
        ctx::Context{S}
    )::InnerParseResult{S} where {T, S, _p, P <: AbstractParser{T, S}}
    parser = p.parser::P
    return parse(parser, ctx)::InnerParseResult{S}
end

@autospecialize p function complete(
        p::ModHelp{T, S, _p, P},
        st::S
    )::ParseResult{T} where {T, S, _p, P <: AbstractParser{T, S}}
    parser = p.parser::P
    return complete(parser, st)::ParseResult{T}
end
