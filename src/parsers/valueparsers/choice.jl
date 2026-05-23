@enum ChoiceValErrCode::UInt8 begin
    CHOICE_Invalid
end

struct ChoiceValError <: AbstractParseError
    code::ChoiceValErrCode
    values::Vector{String}
    got::String
end

function render_error(io::IO, err::ChoiceValError)
    return if err.code == CHOICE_Invalid
        print(io, "Expected one of [$(join(err.values, ','))], got $(err.got)")
    else
        print(io, "unreachable")
    end
end


struct ChoiceVal{T} <: AbstractValueParser{T, ChoiceValError}
    metavar::String
    case_insensitive::Bool
    values::Vector{String}
    outputs::Vector{T}

    ChoiceVal(values::Vector{String}; metavar = "", case_insensitive = true) = let
        normvals = case_insensitive ? map(uppercase, values) : values
        new{String}(metavar, case_insensitive, normvals, normvals)
    end

    ChoiceVal(enumtype::Type{<:Enum}; metavar = "", case_insensitive = true) = let
        enumtypes = instances(enumtype)
        values = collect(string.(enumtypes))
        outputs = collect(enumtypes)
        normvals = case_insensitive ? map(uppercase, values) : values
        new{enumtype}(metavar, case_insensitive, normvals, outputs)
    end
end

default_metavar(::ChoiceVal) = "CHOICE"

(c::ChoiceVal{T})(input::String) where {T} = let
    norminput = c.case_insensitive ? uppercase(input) : input
    index = findfirst(==(norminput), c.values)

    isnothing(index) && return ParseResult{T, ChoiceValError}(
        Err(ChoiceValError(CHOICE_Invalid, c.values, input))
    )

    return ParseResult{T, ChoiceValError}(Ok(c.outputs[index]))

end
