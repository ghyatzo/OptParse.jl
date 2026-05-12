@kwdef struct StringVal{T} <: AbstractValueParser{T}
    metavar::String = ""
    pattern::Regex = r".*"
    allow_empty::Bool = false
end

default_metavar(::StringVal) = "STRING"

@enum StringErrCode::UInt8 begin
    STRING_InvalidPattern
    STRING_IsEmpty
end

stringval_error(code::StringErrCode; token = "", detail = "", subject = "") =
    mkerror(
    ValuePhase, ERR_StringVal, UInt8(code);
    token,
    detail,
    trace = isempty(subject) ? ErrorSite[] : ErrorSite[ErrorSite(ValuePhase, ERR_StringVal, subject)]
)

function stringval_render_error(io::IO, code::StringErrCode, err::ParseError)
    return if code == STRING_InvalidPattern
        print(io, "Expected a string matching the pattern $(err.detail), got $(err.token)")
    elseif code == STRING_IsEmpty
        print(io, "Only non empty strings are allowed. Use str(allow_empty=true), if needed.")
    else
        print(io, "unreachable")
    end
end

(s::StringVal)(input::String)::ParseResult{String} = let
    m = match(s.pattern, input)
    isnothing(m) && return typedErr(
        stringval_error(
            STRING_InvalidPattern;
            token = input,
            detail = string(s.pattern)
        )
    )

    if isempty(input) && !s.allow_empty
        return typedErr(
            stringval_error(
                STRING_IsEmpty
            )
        )
    end
    return typedOk(input)
end
