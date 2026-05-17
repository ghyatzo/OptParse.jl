abstract type AbstractParseError end

# type E will always be Union!
# this is NOT and abstractParseError.
@wrapped struct ParseError{E}
    union::E
end

parse_error(err::E) where {E <: AbstractParseError} = ParseError(err)
parse_error(newerr::E, ::Type{ParseError{U}}) where {E <: AbstractParseError, U <: Union{<:AbstractParseError}} = ParseError{Union{U, E}}(newerr)
widen_error(p::ParseError{U}, ::Type{E}) where {E <: AbstractParseError, U <: Union{<:AbstractParseError}} = ParseError{Union{U, E}}(unwrapunion(p))


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

"""
    ParseException

Exception thrown by [`optparse`](@ref) when parsing fails.
"""
struct ParseException{P <: AbstractParser, E} <: Exception
    parser::P
    argv::Vector{String}
    err::ParseError{E}
end

Base.showerror(io::IO, e::ParseException{P}) where {P <: AbstractParser} = let
    render_error(io, e.err)
    helpdoc = build_help_doc(e.parser, e.argv)
    println(io)
    println(io)
    print(io, "Usage: ")
    render_usage(io, helpdoc)
end
