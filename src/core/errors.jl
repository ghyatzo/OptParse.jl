abstract type AbstractParseError end

# type E will always be Union!
# this is NOT and abstractParseError.
@wrapped struct ParseError{E}
    union::E
end


# Allow automatic widening: ParseError{A} → ParseError{Union{A, B}} when A <: E
Base.convert(::Type{ParseError{E}}, p::ParseError{U}) where {E, U <: E} = ParseError{E}(unwrapunion(p))
# and whenever.
Base.convert(::Type{ParseError{E}}, p::ParseError{B}) where {E, B} = ParseError{Union{E, B}}(unwrapunion(p))



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

Exception thrown by [`optparse`](@ref) when parsing fails.
"""
struct ParseException{P <: AbstractParser, E} <: Exception
    parser::P
    argv::Vector{String}
    err::ParseError{E}
end

ParseException(p::AbstractParser{<:Any, E}, argv::Vector{String}, err::AbstractParseError) where {E} =
    ParseException{typeof(p), E}(p, argv, ParseError(err))

ParseException(p::AbstractParser{<:Any, E}, argv::Vector{String}, perr::ParseError{E2}) where {E, E2<:E} =
    ParseException{typeof(p), E}(p, argv, perr)

Base.showerror(io::IO, e::ParseException{P}) where {P <: AbstractParser} = let
    render_error(io, e.err)
    helpdoc = build_help_doc(e.parser, e.argv)
    println(io)
    println(io)
    print(io, "Usage: ")
    render_usage(io, helpdoc)
end
