@enum IntegerErrCode::UInt8 begin
    INTEGER_Invalid
    INTEGER_BelowMin
    INTEGER_AboveMax
end

struct IntegerValError <: AbstractParseError
    code::IntegerErrCode
    token::String
    detail::String
end

function render_error(io::IO, err::IntegerValError)
    return if err.code == INTEGER_Invalid
        print(io, "Expected a valid integer, got $(err.token)")
    elseif err.code == INTEGER_BelowMin
        print(io, "Value $(err.token) is below the minimum allowed: $(err.detail)")
    elseif err.code == INTEGER_AboveMax
        print(io, "Value $(err.token) is above the maximum allowed: $(err.detail)")
    else
        print(io, "unreachable")
    end
end

@kwdef struct IntegerVal{T} <: AbstractValueParser{T, IntegerValError}
    metavar::String = "INTEGER"
    #
    min::Union{T, Nothing} = nothing
    max::Union{T, Nothing} = nothing
end

(iv::IntegerVal{T})(input::String) where {T} = let
    val = tryparse(T, input)
    if isnothing(val)
        return ParseResult{T, IntegerValError}(Err(IntegerValError(INTEGER_Invalid, input, "")))
    end

    (!isnothing(iv.min) && val < iv.min) && return ParseResult{T, IntegerValError}(Err(IntegerValError(INTEGER_BelowMin, input, string(iv.min))))
    (!isnothing(iv.max) && val > iv.max) && return ParseResult{T, IntegerValError}(Err(IntegerValError(INTEGER_AboveMax, input, string(iv.max))))

    return ParseResult{T, IntegerValError}(Ok(val))
end
