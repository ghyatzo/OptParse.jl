struct ChoiceVal{T} <: AbstractValueParser{T}
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

error_union(::Type{ChoiceVal}) = ChoiceValError

((c::ChoiceVal{T})(input::String)::ParseResult{T}) where {T} = let
    norminput = c.case_insensitive ? uppercase(input) : input
    index = findfirst(==(norminput), c.values)

    isnothing(index) && return typedErr(ChoiceValError(CHOICE_Invalid, c.values, token))

    return typedOk(c.outputs[index])

end
