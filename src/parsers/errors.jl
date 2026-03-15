

@enum ErrorPhase::UInt8 begin
	ParsePhase
	ValuePhase
	CompletePhase
end

@enum ErrorDomain::UInt8 begin
	ERR_ArgFlag
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
	context::Vector{ErrorSite}
end

mkerror(
	phase::ErrorPhase,
	domain::ErrorDomain,
	code::UInt8
	;
	token::String = "",
	detail::String = "",
	context::Vector{ErrorSite} = ErrorSite[]
) = ParseError(phase, domain, code, token, detail, context)

add_context!(err::ParseError, phase::ErrorPhase, domain::ErrorDomain, subject::String) = let
	errsite = ErrorSite(phase, domain, subject)
	# todo, probably trimming error
	push!(err.context, errsite)
end

function render(err::ParseError)
	io = BufferIO()
	if err.domain isa ERR_ArgFlag
		ArgFlag_render_error(io, err)
	elseif err.domain isa ERR_ArgArgument
		ArgArgument_render_error(io, err)
	elseif err.domain isa ERR_ArgOption
		ArgOption_render_error(io, err)
	elseif err.domain isa ERR_ArgCommand
		ArgCommand_render_error(io, err)
	elseif err.domain isa ERR_ConstrObject
		ConstrObject_render_error(io, err)
	elseif err.domain isa ERR_ConstrOr
		ConstrOr_render_error(io, err)
	elseif
		...
	else
		print(io, "Unreachable")
	end

	return io
end

