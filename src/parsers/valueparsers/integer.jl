@kwdef struct IntegerVal{T}
    metavar::String = "INTEGER"
    #
    type::Type = T
    min::Union{Int, Nothing} = nothing
    max::Union{Int, Nothing} = nothing
end


@enum IntegerErrCode::UInt8 begin
    INTEGER_Invalid
    INTEGER_BelowMin
    INTEGER_AboveMax
end

integerval_error(code::IntegerErrCode; token="", detail="", subject="") =
    mkerror(ValuePhase, ERR_IntegerVal, UInt8(code);
        token,
        detail,
        context= isempty(subject) ? ErrorSite[] : ErrorSite[ErrorSite(ValuePhase, ERR_IntegerVal, subject)]
    )

function integerval_render_error(io::IO, code::IntegerErrCode, err::ParseError)
    if code == INTEGER_Invalid
        print(io, "Expected valid integer, got $(err.token)")
    elseif code == INTEGER_BelowMin
        print(io, "Value $(err.token) is below the minimum allowed: $(err.detail)")
    elseif code == INTEGER_AboveMax
        print(io, "Value $(err.token) is above the maximum allowed: $(err.detail)")
    else
        print(io, "unreachable")
    end
end


((iv::IntegerVal{T})(input::String)::Result{T, String}) where {T} = let
    val = tryparse(T, input)
    if isnothing(val)
        return typedErr(integerval_error(
            INTEGER_Invalid;
            token=input
        ))
    end

    (!isnothing(iv.min) && val < iv.min) && return typedErr(integerval_error(INTEGER_BelowMin; token=input, detail=string(iv.min)))
    (!isnothing(iv.max) && val > iv.max) && return typedErr(integerval_error(INTEGER_AboveMax; token=input, detaul=string(iv.max)))

    return typedOk(val)
end
