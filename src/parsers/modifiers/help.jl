struct ModHelp{T, E, S, P, R} <: AbstractParser{T, E, S, P, R}
    initialState::S
    parser::P
    info::HelpInfo
end

ModHelp(parser::P, info::HelpInfo) where {P <: AbstractParser} =
    ModHelp{
    tval(P),
    terr(P),
    tstate(P),
    P,
    priority(P),
}(parser.initialState, parser, info)

ModHelp(parser::ModHelp, info::HelpInfo) =
    ModHelp(parser.parser, merge_helpinfo(parser.info, info))

@autospecialize p function usage(p::ModHelp{T, E, S, P}) where {T, E, S, P <: AbstractParser{T, E, S}}
    child_usage = usage(p.parser)::UsageNode
    return ishidden(p.info) ? UsageHidden(child_usage) : child_usage
end

@autospecialize p function helpentries(p::ModHelp{T, E, S, P}, rt::OverlayContext) where {T, E, S, P <: AbstractParser{T, E, S}}
    parser = p.parser::P
    return ishidden(p.info) ? HelpEntry[] :
        helpentries(parser, with_helpinfo(rt, p.info))::Vector{HelpEntry}
end

@autospecialize p ctx function focused_helpdoc(
        p::ModHelp{T, E, S, P},
        ctx::Context{S},
        prefix::Vector{String},
        rt::OverlayContext
    )::HelpDoc where {T, E, S, P <: AbstractParser{T, E, S}}
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
        p::ModHelp{T, E, S, P},
        ctx::Context{S}
    ) where {T, E, S, P <: AbstractParser{T, E, S}}
    parser = p.parser::P
    return parse(parser, ctx)
end

@autospecialize p function complete(
        p::ModHelp{T, E, S, P},
        st::S
    ) where {T, E, S, P <: AbstractParser{T, E, S}}
    parser = p.parser::P
    return complete(parser, st)
end
