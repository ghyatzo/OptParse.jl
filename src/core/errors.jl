
@enum ErrorPhase::UInt8 begin
	ParsePhase
	ValuePhase
	CompletePhase
end

@enum ErrorDomain::UInt8 begin
	ERR_Main

	ERR_ArgGate
	ERR_ArgArgument
	ERR_ArgOption
	ERR_ArgCommand

	ERR_ConstrObject
	ERR_ConstrOr
	ERR_ConstrTuple

	ERR_ModWithDefault
	ERR_ModMultiple

	ERR_StringVal
	ERR_ChoiceVal
	ERR_IntegerVal
	ERR_FloatVal
	ERR_UUIDVal
	ERR_PathVal
end

struct ErrorSite
	phase::ErrorPhase
	domain::ErrorDomain
	subject::String
end

struct ParseError
	phase::ErrorPhase
	domain::ErrorDomain
	code::UInt8
	token::String
	detail::String
	trace::Vector{ErrorSite}
end

mkerror(
	phase::ErrorPhase,
	domain::ErrorDomain,
	code::UInt8,
	;
	token::String = "",
	detail::String = "",
	trace::Vector{ErrorSite} = ErrorSite[]
) = ParseError(phase, domain, code, token, detail, trace)


@enum MainErrCode::UInt8 begin
    MAIN_NoProgress
end

main_error(code::MainErrCode; token="", detail="", subject="") =
    mkerror(ParsePhase, ERR_Main, UInt8(code);
        token,
        detail,
        trace= isempty(subject) ? ErrorSite[] : ErrorSite[ErrorSite(ParsePhase, ERR_Main, subject)]
    )

function main_render_error(io::IO, code::MainErrCode, err::ParseError)
    if code == MAIN_NoProgress
        if isempty(err.token)
            print(io, "Parser made no progress")
        else
            print(io, "Unexpected option or argument: $(err.token)")
        end
    else
        print(io, "unreachable")
    end
end


# rendering engine

function render_error(io::IO, err::ParseError)
	render_error_subject(io, err)
	render_error_payload(io, err)
end

function render_error_subject(io::IO, err::ParseError)
	if !isempty(err.trace)
		print(io, last(err.trace).subject)
		print(io, ": ")
	end
end

function render_error_payload(io::IO, err::ParseError)
	if err.domain == ERR_Main
		main_render_error(io, MainErrCode(err.code), err)
	elseif err.domain == ERR_ArgGate
		arggate_render_error(io, GateErrCode(err.code), err)
	elseif err.domain == ERR_ArgArgument
		argargument_render_error(io, ArgumentErrCode(err.code), err)
	elseif err.domain == ERR_ArgOption
		argoption_render_error(io, OptionErrCode(err.code), err)
	elseif err.domain == ERR_ArgCommand
		argcommand_render_error(io, CommandErrCode(err.code), err)
	elseif err.domain == ERR_ConstrObject
		constrobject_render_error(io, ObjectErrCode(err.code), err)
	elseif err.domain == ERR_ConstrOr
		constror_render_error(io, OrErrCode(err.code), err)
	elseif err.domain == ERR_ConstrTuple
		constrtuple_render_error(io, TupleErrCode(err.code), err)
	elseif err.domain == ERR_ModWithDefault
		modwithdefault_render_error(io, WithDefaultErrCode(err.code), err)
	elseif err.domain == ERR_ModMultiple
		modmultiple_render_error(io, MultipleErrCode(err.code), err)
	elseif err.domain == ERR_StringVal
		stringval_render_error(io, StringErrCode(err.code), err)
	elseif err.domain == ERR_ChoiceVal
		choice_render_error(io, ChoiceErrCode(err.code), err)
	elseif err.domain == ERR_IntegerVal
		integerval_render_error(io, IntegerErrCode(err.code), err)
	elseif err.domain == ERR_FloatVal
		floatval_render_error(io, FloatErrCode(err.code), err)
	elseif err.domain == ERR_UUIDVal
		uuidval_render_error(io, UUIDErrCode(err.code), err)
	elseif err.domain == ERR_PathVal
		pathval_render_error(io, PathErrCode(err.code), err)
	else
		print(io, "Unreachable")
	end
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
struct ParseException <: Exception
	err::ParseError
end

Base.showerror(io::IO, e::ParseException) = let
	render_error(io, e.err)
end
