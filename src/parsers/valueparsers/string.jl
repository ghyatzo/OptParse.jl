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

struct StringValError <: AbstractParseError
    code::StringErrCode
    token::String
    pattern::String
end

function render_error(io::IO, err::StringValError)
    return if err.code == STRING_InvalidPattern
        print(io, "Expected a string matching the pattern $(err.pattern), got $(err.token)")
    elseif err.code == STRING_IsEmpty
        print(io, "Only non empty strings are allowed. Use str(allow_empty=true), if needed.")
    else
        print(io, "unreachable")
    end
end

(s::StringVal)(input::String)::ParseResult{String} = let
    m = match(s.pattern, input)
    isnothing(m) && return typedErr(
        StringValError(STRING_InvalidPattern, input, string(s.pattern))
    )

    if isempty(input) && !s.allow_empty
        return typedErr(
            StringValError(STRING_IsEmpty, "", "")
        )
    end
    return typedOk(input)
end
