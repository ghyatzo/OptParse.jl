const ConstantState{X} = Val{X}

struct ArgConstant{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    _dummy::P
end

ArgConstant(val::T) where {T} = let
    try
        ArgConstant{typeof(Val(val)), typeof(Val(val)), 0, Nothing}(Val(val), nothing)
    catch e
        e isa TypeError && ArgumentError("Constant only supports isbits types or Symbols.")
        throw(e)
    end
end

function parse(::ArgConstant{Val{val}, ConstantState{val}}, ctx::Context{ConstantState{val}})::ParseResult{ConstantState{val}, String} where {val}
    return Ok(ParseSuccess(consumed_empty(ctx), ctx))
end

function complete(::ArgConstant{Val{val}, ConstantState{val}}, st::ConstantState{val})::Result{Val{val}, String} where {val}
    return Ok(st)
end
