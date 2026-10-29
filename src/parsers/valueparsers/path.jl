@enum PathKind::UInt8 begin
    PATH_Any
    PATH_File
    PATH_Directory
end

@enum PathErrCode::UInt8 begin
    PATH_Empty
    PATH_NotFound
    PATH_NotAbsolute
    PATH_NotFile
    PATH_NotDirectory
end

struct PathValError <: AbstractParseError
    code::PathErrCode
    token::String
end

function render_error(io::IO, err::PathValError)
    return if err.code == PATH_Empty
        print(io, "Path cannot be empty")
    elseif err.code == PATH_NotFound
        print(io, "Could not find path specified: '$(err.token)'")
    elseif err.code == PATH_NotAbsolute
        print(io, "Expected an absolute path, got '$(err.token)'")
    elseif err.code == PATH_NotFile
        print(io, "Expected a file, got '$(err.token)'")
    elseif err.code == PATH_NotDirectory
        print(io, "Expected a directory, got '$(err.token)'")
    else
        @assert false "unreachable"
    end
end

@kwdef struct PathVal{T} <: AbstractValueParser{T, PathValError}
    metavar::String = "PATH"
    kind::PathKind = PATH_Any
    absolute::Bool = false
end


(p::PathVal{T})(input::AbstractString) where {T} = let
    isempty(input) && return Result{T, PathValError}'.Err(PathValError(PATH_Empty, ""))

    if p.absolute && !isabspath(input)
        return Result{T, PathValError}'.Err(PathValError(PATH_NotAbsolute, String(input)))
    end

    if p.kind == PATH_File
        !ispath(input) && return Result{T, PathValError}'.Err(PathValError(PATH_NotFound, String(input)))
        !isfile(input) && return Result{T, PathValError}'.Err(PathValError(PATH_NotFile, String(input)))
    elseif p.kind == PATH_Directory
        !ispath(input) && return Result{T, PathValError}'.Err(PathValError(PATH_NotFound, String(input)))
        !isdir(input) && return Result{T, PathValError}'.Err(PathValError(PATH_NotDirectory, String(input)))
    end

    return Result{T, PathValError}'.Ok(String(input))
end
