@kwdef struct PathVal{T}
	metavar::String = ""
	absolute::Bool = false
end

default_metavar(::PathVal) = "PATH"

@enum PathErrCode::UInt8 begin
	PATH_NotFound
	PATH_NotAbsolute
end

pathval_error(code::PathErrCode; token = "", detail = "", subject = "")=
	mkerror(ValuePhase, ERR_PathVal, UInt8(code);
		token,
		detail,
		context = isempty(subject) ? ErrorSite[] : ErrorSite[ErrorSite(ValuePhase, ERR_PathVal, subject)]
	)

function pathval_render_error(io::IO, code::StringErrCode, err::ParseError)
	if code == PATH_NotFound
		print(io, "Could not find path specified: '$(err.token)'")
	elseif code == PATH_NotAbsolute
		print(io, "Expected an absolute path, got '$(err.token)'")
	else
		print(io, "unreachable")
	end
end

(p::PathVal)(input::String)::ParseResult{String} = let
	!isfile(input) && return typedErr(pathval_error(
		PATH_NotFound;
		token=input
	))

	if p.absolute && !isabspath(input)
		return typedErr(pathval_error(
			PATH_NotAbsolute;
			token = input
		))
	end

	return typedOk(input)
end