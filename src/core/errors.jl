abstract type AbstractParseError end

# type E will always be Union!
# this is NOT and abstractParseError.
@wrapped struct ParseError{E}
    union::E
end


# Allow automatic widening: ParseError{A} → ParseError{Union{A, B}} when A <: E
Base.convert(::Type{ParseError{E}}, p::ParseError{U}) where {E, U <: E} = ParseError{E}(unwrapunion(p))
# and whenever.
Base.convert(::Type{ParseError{E}}, p::ParseError{B}) where {E, B} = ParseError{joinerr(E, B)}(unwrapunion(p))

# Combine error-type parameters, dropping the `Uninit` sentinel that parsers
# which cannot fail carry in place of an error type, so that `E` is always a
# union of concrete error types. Fold several with
# `reduce(joinerr, errs, init = other_err)`. Foldable so the result is a
# constant wherever it appears in a type position or annotation.
Base.@assume_effects :foldable joinerr(::Type{A}, ::Type{B}) where {A, B} = Union{A, B}
Base.@assume_effects :foldable joinerr(::Type{Uninit}, ::Type{B}) where {B} = Union{B}
Base.@assume_effects :foldable joinerr(::Type{A}, ::Type{Uninit}) where {A} = Union{A}

@enum MainErrCode::UInt8 begin
    MAIN_NoProgress
    MAIN_UnexpectedToken
end

struct MainError <: AbstractParseError
    code::MainErrCode
    token::String
end

function render_error(io::IO, err::MainError)
    return if err.code == MAIN_NoProgress
        print(io, "Parser made no progress")
    elseif err.code == MAIN_UnexpectedToken
        print(io, "Unexpected option or argument: $(err.token)")
    else
        print(io, "unreachable")
    end
end


# rendering engine

function render_error(io::IO, err::ParseError)
    return @unionsplit render_error(io, err)
end

Base.string(perr::ParseError) = let
    io = IOBuffer()
    render_error(io, perr)
    return String(take!(io))
end

Base.string(err::AbstractParseError) = string(ParseError(err))

"""
    ParseException

Parser, arguments, structured error, and optional program name used to render a
parse failure. [`optparse`](@ref) prints this diagnostic through `showerror` and
returns `nothing`; it does not throw this exception.
"""
struct ParseException{P <: AbstractParser, E} <: Exception
    parser::P
    argv::Vector{String}
    err::ParseError{E}
    progname::String
end

ParseException{P, E}(p::P, argv::Vector{String}, err::ParseError{E}) where {P <: AbstractParser, E} =
    ParseException{P, E}(p, argv, err, "")

ParseException(p::AbstractParser{<:Any, E}, argv::Vector{String}, err::AbstractParseError; progname::AbstractString = "") where {E} =
    ParseException{typeof(p), E}(p, argv, ParseError(err), String(progname))

ParseException(p::AbstractParser{<:Any, E}, argv::Vector{String}, perr::ParseError{E2}; progname::AbstractString = "") where {E, E2<:E} =
    ParseException{typeof(p), E}(p, argv, perr, String(progname))

Base.showerror(io::IO, e::ParseException{P}) where {P <: AbstractParser} = let
    render_error(io, e.err)
    helpdoc = build_help_doc(e.parser, e.argv)
    println(io)
    println(io)
    print(io, "Usage: ")
    render_usage(io, helpdoc; progname = e.progname)
end
