struct Choice{T}
    metavar::String
    caseInsensitive::Bool
    values::Vector{String}
    outputs::Vector{T}

    Choice(values::Vector{String}; metavar = "", caseInsensitive = true) = let
        normvals = caseInsensitive ? map(uppercase, values) : values
        new{String}(metavar, caseInsensitive, normvals, normvals)
    end

    Choice(enumtype::Type{<:Enum}; metavar = "", caseInsensitive = true ) = let
        enumtypes = instances(enumtype)
        values = collect(string.(enumtypes))
        outputs = collect(enumtypes)
        normvals = caseInsensitive ? map(uppercase, values) : values
        new{enumtype}(metavar, caseInsensitive, normvals, outputs)
    end
end

default_metavar(::Choice) = "CHOICE"

@enum ChoiceErrCode::UInt8 begin
    CHOICE_Invalid
end

choice_error(code::ChoiceErrCode; token="", detail="", subject="") =
    mkerror(ValuePhase, ERR_ChoiceVal, UInt8(code);
        token,
        detail,
        trace= isempty(subject) ? ErrorSite[] : ErrorSite[ErrorSite(ValuePhase, ERR_ChoiceVal, subject)]
    )

function choice_render_error(io::IO, code::ChoiceErrCode, err::ParseError)
    if code == CHOICE_Invalid
        print(io, "Expected one of [$(err.detail)], got $(err.token)")
    else
        print(io, "unreachable")
    end
end

((c::Choice{T})(input::String)::ParseResult{T}) where {T} = let
    norminput = c.caseInsensitive ? uppercase(input) : input
    index = findfirst(==(norminput), c.values)

    isnothing(index) && return typedErr(choice_error(
        CHOICE_Invalid;
        token = input,
        detail = join(c.values, ',')
    ))

    return typedOk(c.outputs[index])

end
