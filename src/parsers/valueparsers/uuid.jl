@enum UUIDErrCode::UInt8 begin
    UUID_Invalid
    UUID_WrongVersion
end

struct UUIDValError <: AbstractParseError
    code::UUIDErrCode
    token::String
    allowed_versions::String
end

function render_error(io::IO, err::UUIDValError)
    return if err.code == UUID_Invalid
        print(io, "Malformed UUID string: $(err.token)")
    elseif err.code == UUID_WrongVersion
        print(io, "Expected a UUID of version [$(err.allowed_versions)], got version $(err.token)")
    else
        print(io, "unreachable")
    end
end

@kwdef struct UUIDVal{T} <: AbstractValueParser{T, UUIDValError}
    metavar::String = "UUID"
    #
    allowed_versions::Vector{Int} = Int[]
end

(u::UUIDVal)(input::String)= let

    maybeuuid = try
        UUID(input)
    catch
        nothing
    end
    if isnothing(maybeuuid)
        return ParseResult{UUID, UUIDValError}(Err(
            UUIDValError(UUID_Invalid, input, "")
        ))
    end

    version = uuid_version(maybeuuid)
    if isempty(u.allowed_versions) || version ∈ u.allowed_versions
        return ParseResult{UUID, UUIDValError}(Ok(maybeuuid))
    end

    return ParseResult{UUID, UUIDValError}(Err(
        UUIDValError(UUID_WrongVersion, string(version), join(u.allowed_versions, ','))
    ))
end
