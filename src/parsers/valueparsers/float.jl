@kwdef struct FloatVal{T} <: AbstractValueParser{T}
    metavar::String = ""
    #
    min::Union{T, Nothing} = nothing
    max::Union{T, Nothing} = nothing
    allow_infinity::Bool = false
    allow_nan::Bool = false
end

default_metavar(::FloatVal) = "FLOAT"

@enum FloatErrCode::UInt8 begin
    FLOAT_Invalid
    FLOAT_BelowMin
    FLOAT_AboveMax
    FLOAT_NoInf
    FLOAT_NoNaN
end

struct FloatValError <: AbstractParseError
    code::FloatErrCode
    token::String
    detail::String
end

function render_error(io::IO, err::FloatValError)
    return if err.code == FLOAT_Invalid
        print(io, "Expected a valid float, got $(err.token)")
    elseif err.code == FLOAT_BelowMin
        print(io, "Value $(err.token) is below the minimum allowed: $(err.detail)")
    elseif err.code == FLOAT_AboveMax
        print(io, "Value $(err.token) is above the maximum allowed: $(err.detail)")
    elseif err.code == FLOAT_NoInf
        print(io, "Infinite floats are not allowed")
    elseif err.code == FLOAT_NoNaN
        print(io, "NaNs are not allowed")
    else
        print(io, "unreachable")
    end
end


((f::FloatVal{T})(input::String)::ParseResult{T}) where {T} = let
    val = tryparse(T, input)
    if isnothing(val)
        return typedErr(FloatValError(FLOAT_Invalid, input, ""))
    end

    if isinf(val) && !f.allow_infinity
        return typedErr(FloatValError(FLOAT_NoInf, input, ""))
    end

    if isnan(val) && !f.allow_nan
        return typedErr(FloatValError(FLOAT_NoNaN, input, ""))
    end

    (!isnothing(f.min) && val < f.min) && return typedErr(FloatValError(FLOAT_BelowMin, input, string(f.min)))
    (!isnothing(f.max) && val > f.max) && return typedErr(FloatValError(FLOAT_AboveMax, input, string(f.max)))


    return typedOk(val)
end
