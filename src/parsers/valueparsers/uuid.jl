@kwdef struct UUIDVal{T} <: AbstractValueParser{T}
    metavar::String = ""
    #
    allowed_versions::Vector{Int} = Int[]
end

default_metavar(::UUIDVal) = "UUID"

@enum UUIDErrCode::UInt8 begin
    UUID_Invalid
    UUID_WrongVersion
end

uuidval_error(code::UUIDErrCode; token = "", detail = "", subject = "") =
    mkerror(
    ValuePhase, ERR_UUIDVal, UInt8(code);
    token,
    detail,
    trace = isempty(subject) ? ErrorSite[] : ErrorSite[ErrorSite(ValuePhase, ERR_UUIDVal, subject)]
)

function uuidval_render_error(io::IO, code::UUIDErrCode, err::ParseError)
    return if code == UUID_Invalid
        print(io, "Malformed UUID string: $(err.token)")
    elseif code == UUID_WrongVersion
        print(io, "Expected a UUID of version [$(err.detail)], got version $(err.token)")
    else
        print(io, "unreachable")
    end
end

((u::UUIDVal)(input::String)::ParseResult{UUID}) = let

    maybeuuid = try
        UUID(input)
    catch
        nothing
    end
    if isnothing(maybeuuid)
        # return typedErr("Malformed UUID string: `$input`.")
        return typedErr(
            uuidval_error(
                UUID_Invalid;
                token = input
            )
        )
    end

    version = uuid_version(maybeuuid)
    if isempty(u.allowed_versions) || version ∈ u.allowed_versions
        return typedOk(maybeuuid)
    end

    # return typedErr("Expected UUID of version [$(join(u.allowed_versions, ','))], but got version $version")
    return typedErr(
        uuidval_error(
            UUID_WrongVersion;
            token = string(version),
            detail = join(u.allowed_versions, ',')
        )
    )
end
