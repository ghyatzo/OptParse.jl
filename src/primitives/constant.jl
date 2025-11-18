struct ArgConstant{T, S, p, P}
    initialState::S
    _dummy::P
end

ArgConstant(val::T) where {T} = let
    try
        ArgConstant{T, Result{typeof(Val(val)), String}, 0, Nothing}(Ok(Val(val)), nothing)
    catch e
        e isa TypeError && ArgumentError("Constant does not support Strings in its types, use Symbols instead.")
        throw(e)
    end
end

ArgConstant(val::String) = error("Constant does not support plain Strings, use Symbols instead.")

function parse(p::ArgConstant{T, Result{Val{val}, String}}, ctx::Context)::ParseResult{Result{Val{val}, String}, String} where {T, val}
    constctx = @set ctx.state = Result{Val{val}, String}(Ok(Val(val)))
    return ParseOk(String[], constctx)
end

function complete(p::ArgConstant{T, Result{Val{val}, String}}, ::Result{Val{val},String})::Result{T, String} where {T, val}
    return Ok(convert(T, val))
end
