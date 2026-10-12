@enum DateErrCode::UInt8 begin
    DATE_Invalid
    DATE_TooEarly
    DATE_TooLate
end

struct DateValError <: AbstractParseError
    code::DateErrCode
    token::String
    detail::String
end

function render_error(io::IO, err::DateValError)
    return if err.code == DATE_Invalid
        print(io, "Expected a valid date, got $(err.token)")
    elseif err.code == DATE_TooEarly
        print(io, "Value $(err.token) is before the earliest allowed date: $(err.detail)")
    elseif err.code == DATE_TooLate
        print(io, "Value $(err.token) is after the latest allowed date: $(err.detail)")
    else
        print(io, "unreachable")
    end
end

_as_format(f::DateFormat) = f
_as_format(f::AbstractString) = DateFormat(f)

@kwdef struct DateVal{T, F <: DateFormat} <: AbstractValueParser{T, DateValError}
    metavar::String = "DATE"
    #
    format::F
    after::Union{T, Nothing} = nothing
    before::Union{T, Nothing} = nothing
end

DateVal{T}(; format, kw...) where {T} = let
    fmt = _as_format(format)
    DateVal{T, typeof(fmt)}(; format = fmt, kw...)
end

# The format is the grammar: `DateFormat` parsing rejects extra trailing
# input, accepts unpadded field widths, and gives missing trailing fields
# their earliest values.
(dv::DateVal{T})(input::String) where {T} = let
    val = try
        Base.parse(T, input, dv.format)
    catch e
        e isa ArgumentError || rethrow()
        nothing
    end
    isnothing(val) && return Result{T, DateValError}'.Err(DateValError(DATE_Invalid, input, ""))

    (!isnothing(dv.after) && val < dv.after) &&
        return Result{T, DateValError}'.Err(DateValError(DATE_TooEarly, input, format(dv.after, dv.format)))
    (!isnothing(dv.before) && val > dv.before) &&
        return Result{T, DateValError}'.Err(DateValError(DATE_TooLate, input, format(dv.before, dv.format)))

    return Result{T, DateValError}'.Ok(val)
end
