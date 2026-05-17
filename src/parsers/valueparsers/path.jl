@kwdef struct PathVal{T} <: AbstractValueParser{T}
    metavar::String = ""
    absolute::Bool = false
end

default_metavar(::PathVal) = "PATH"

@enum PathErrCode::UInt8 begin
    PATH_NotFound
    PATH_NotAbsolute
end

struct PathValError <: AbstractParseError
    code::PathErrCode
    token::String
end

function render_error(io::IO, err::PathValError)
    return if err.code == PATH_NotFound
        print(io, "Could not find path specified: '$(err.token)'")
    elseif err.code == PATH_NotAbsolute
        print(io, "Expected an absolute path, got '$(err.token)'")
    else
        print(io, "unreachable")
    end
end

(p::PathVal)(input::String)::ParseResult{String} = let
    # TODO, finish this up properly.
    !isfile(input) && return typedErr(PathValError(PATH_NotFound, input))

    if p.absolute && !isabspath(input)
        return typedErr(PathValError(PATH_NotAbsolute, input))
    end

    return typedOk(input)
end
