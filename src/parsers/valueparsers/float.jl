@kwdef struct FloatVal{T}
    metavar::String = "FLOAT"
    #
    type::Type = T
    min::Union{T, Nothing} = nothing
    max::Union{T, Nothing} = nothing
    allowInfinity::Bool = false
    allowNan::Bool = false
end

@enum FloatErrCode::UInt8 begin
    FLOAT_Invalid
    FLOAT_BelowMin
    FLOAT_AboveMax
    FLOAT_NoInf
    FLOAT_NoNaN
end

floatval_error(code::FloatErrCode; token="", detail="", subject="") =
    mkerror(ValuePhase, ERR_FloatVal, UInt8(code);
        token,
        detail,
        context= isempty(subject) ? ErrorSite[] : ErrorSite[ErrorSite(ValuePhase, ERR_FloatVal, subject)]
    )

function floatval_render_error(io::IO, code::FloatErrCode, err::ParseError)
    if code == FLOAT_Invalid
        print(io, "Expected a valid float, got $(err.token)")
    elseif code == FLOAT_BelowMin
        print(io, "Value $(err.token) is below the minimum allowed: $(err.detail)")
    elseif code == FLOAT_AboveMax
        print(io, "Value $(err.token) is above the maximum allowed: $(err.detail)")
    elseif code == FLOAT_NoInf
        print(io, "Infinite floats are not allowed")
    elseif code == FLOAT_NoNaN
        print(io, "NaNs are not allowed")
    else
        print(io, "unreachable")
    end
end


((f::FloatVal{T})(input::String)::ParseResult{T}) where {T} = let
    val = tryparse(T, input)
    if isnothing(val)
        return typedErr(floatval_error(FLOAT_Invalid; token=input))
        # return typedErr("Expected valid float, got `$input`")
    end

    if isinf(val) && !f.allowInfinity
        return typedErr(floatval_error(FLOAT_NoInf; token=input))
        # return typedErr("Infinite floats are not allowed.")
    end

    if isnan(val) && !f.allowNan
        return typedErr(floatval_error(FLOAT_NoNaN; token=input))
        # return typedErr("NaNs are not allowed.")
    end

    (!isnothing(f.min) && val < f.min) && return typedErr(floatval_error(FLOAT_BelowMin; token=input, detail=string(f.min)))
    (!isnothing(f.max) && val > f.max) && return typedErr(floatval_error(FLOAT_AboveMax; token=input, detail=string()))
    # (!isnothing(f.min) && val < f.min) && return typedErr("Value $input is below the minimum: $(f.min)")
    # (!isnothing(f.max) && val > f.max) && return typedErr("Value $input is above the maximum: $(f.max)")

    return typedOk(val)
end
