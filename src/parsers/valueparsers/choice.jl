@kwdef struct Choice{T}
    metavar::String = "CHOICE"
    caseInsensitive::Bool = true
    values::Vector{String}

    Choice(metavar, caseInsensitive, values::Vector{String}) = let
        normvals = caseInsensitive ? map(lowercase, values) : values
        new{String}(metavar, caseInsensitive, normvals)
    end
end

@enum ChoiceErrCode::UInt8 begin
    CHOICE_Invalid
end

choice_error(code::ChoiceErrCode; token="", detail="", subject="") =
    mkerror(ValuePhase, ERR_ChoiceVal, UInt8(code);
        token,
        detail,
        context= isempty(subject) ? ErrorSite[] : ErrorSite[ErrorSite(ValuePhase, ERR_ChoiceVal, subject)]
    )

function choice_render_error(io::IO, code::ChoiceErrCode, err::ParseError)
    # pass
end

(c::Choice)(input::String)::Result{String, String} = let
    norminput = c.caseInsensitive ? lowercase(input) : input
    index = findfirst(==(norminput), c.values)

    isnothing(index) && return typedErr(choice_error(
        CHOICE_Invalid;
        token = input,
        detail = join(c.values, ',')
    ))
    # isnothing(index) && return typedErr("Expected one of $(join(c.values, ',')), but got $input")
    return typedOk(c.values[index])
end
