@kwdef struct StringVal{T}
    metavar::String = ""
    pattern::Regex = r".*"
end

default_metavar(::StringVal) = "STRING"

@enum StringErrCode::UInt8 begin
    STRING_InvalidPattern
end

stringval_error(code::StringErrCode; token = "", detail ="", subject="") =
    mkerror(ValuePhase, ERR_StringVal, UInt8(code);
        token,
        detail,
        context= isempty(subject) ? ErrorSite[] : ErrorSite[ErrorSite(ValuePhase, ERR_StringVal, subject)]
    )

function stringval_render_error(io::IO, code::StringErrCode, err::ParseError)
    if code == STRING_InvalidPattern
        print(io, "Expected a string matching the pattern $(err.detail), got $(err.token)")
    else
        print(io, "unreachable")
    end
end

(s::StringVal)(input::String)::ParseResult{String} = let
    m = match(s.pattern, input)
    isnothing(m) && return typedErr(stringval_error(
        STRING_InvalidPattern;
        token=input,
        detail=string(s.pattern)
    ))
    # isnothing(m) && return typedErr("Expected a string matching the pattern `$(s.pattern)`, but got `$input`.")
    return typedOk(input)
end
