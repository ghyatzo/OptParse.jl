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


((iv::IntegerVal{T})(input::String)::Result{T, String}) where {T} = let
    val = tryparse(T, input)
    if isnothing(val)
        # return typedErr("Expected valid integer, got `$input`")
        return typedErr(integerval_error(
            INTEGER_Invalid;
            token=input
        ))
    end

    # (!isnothing(iv.min) && val < iv.min) && return typedErr("Value $input is below the minimum: $(iv.min)")
    # (!isnothing(iv.max) && val > iv.max) && return typedErr("Value $input is above the maximum: $(iv.max)")
    (!isnothing(iv.min) && val < iv.min) && return typedErr(integerval_error(INTEGER_BelowMin; token=input, detail=string(iv.min)))
    (!isnothing(iv.max) && val > iv.max) && return typedErr(integerval_error(INTEGER_AboveMax; token=input, detaul=string(iv.max)))

    return typedOk(val)
end
