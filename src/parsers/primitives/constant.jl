const ConstantState{X} = Val{X}

struct ArgConstant{T, E, S, P, R} <: AbstractParser{T, E, S, P, R}
    initialState::S
    _dummy::P

    ArgConstant(val::T) where {T} = let
        try
            new{typeof(Val(val)), Uninit, typeof(Val(val)), Nothing, 0}(Val(val), nothing)
        catch e
            e isa TypeError && ArgumentError("Constant only supports isbits types or Symbols.")
            throw(e)
        end
    end
end



usage(p::ArgConstant) = UsageHidden(UsageEmpty())
helpentries(p::ArgConstant, rt::OverlayContext) = [HelpEntry(usage(p), helpinfo(rt))]
focused_helpdoc(
    p::ArgConstant{Val{val}, Uninit, ConstantState{val}},
    ::Context{ConstantState{val}},
    prefix::Vector{String},
    rt::OverlayContext
) where {val} = HelpDoc(prefix, usage(p), helpinfo(rt), HelpEntry[])

function parse(::ArgConstant{Val{val}, <:Any, ConstantState{val}}, ctx::Context{ConstantState{val}}) where {val}
    return InnerResult{ConstantState{val}, Uninit}(innerOk(ctx, consumed_empty(ctx)))
end

function complete(::ArgConstant{Val{val}, <:Any, ConstantState{val}}, st::ConstantState{val}) where {val}
    return Result{Val{val}, Uninit}(Ok(st))
end
