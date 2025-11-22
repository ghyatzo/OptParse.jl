const ConstantState{X} = Val{X}

struct ArgConstant{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    _dummy::P
end

ArgConstant(val::T) where {T} = let
    try
        ArgConstant{T, typeof(Val(val)), 0, Nothing}(Val(val), nothing)
    catch e
        e isa TypeError && ArgumentError("Constant only supports isbits types or Symbols.")
        throw(e)
    end
end

function parse(p::ArgConstant{T, ConstantState{val}}, ctx::Context{ConstantState{val}})::ParseResult{ConstantState{val}, String} where {T, val}
    constctx = @set ctx.state = Val(val)
    return ParseOk(String[], constctx)
end

function complete(p::ArgConstant{T, ConstantState{val}}, ::ConstantState{val})::Result{T, String} where {T, val}
    return Ok(convert(T, val))
end
