struct Choice{T} <: AbstractValueParser{T}
    metavar::String
    case_insensitive::Bool
    values::Vector{String}
    outputs::Vector{T}

    Choice(values::Vector{String}; metavar = "", case_insensitive = true) = let
        normvals = case_insensitive ? map(uppercase, values) : values
        new{String}(metavar, case_insensitive, normvals, normvals)
    end

    Choice(enumtype::Type{<:Enum}; metavar = "", case_insensitive = true) = let
        enumtypes = instances(enumtype)
        values = collect(string.(enumtypes))
        outputs = collect(enumtypes)
        normvals = case_insensitive ? map(uppercase, values) : values
        new{enumtype}(metavar, case_insensitive, normvals, outputs)
    end
end

default_metavar(::Choice) = "CHOICE"

@enum ChoiceErrCode::UInt8 begin
    CHOICE_Invalid
end

choice_error(code::ChoiceErrCode; token = "", detail = "") =
    mkerror(
    ERR_ChoiceVal, UInt8(code);
    token,
    detail
)

function choice_render_error(io::IO, code::ChoiceErrCode, err::ParseError)
    return if code == CHOICE_Invalid
        print(io, "Expected one of [$(err.detail)], got $(err.token)")
    else
        print(io, "unreachable")
    end
end

((c::Choice{T})(input::String)::ParseResult{T}) where {T} = let
    norminput = c.case_insensitive ? uppercase(input) : input
    index = findfirst(==(norminput), c.values)

    isnothing(index) && return typedErr(
        choice_error(
            CHOICE_Invalid;
            token = input,
            detail = join(c.values, ',')
        )
    )

    return typedOk(c.outputs[index])

end
