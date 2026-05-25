module FastIdentifiersExt

using OptParse
using OptParse.ErrorTypes

using OptParse: AbstractParseError, AbstractValueParser, ParseResult
using FastIdentifiers

@enum IdentifierValErrCode::UInt8 begin
	IDENTIFIER_Malformed
	IDENTIFIER_Checksum
	IDENTIFIER_OtherError
end

struct IdentifierValError <: AbstractParseError
	code::IdentifierValErrCode
	msg::String
end

IdentifierValError(e::FastIdentifiers.MalformedIdentifier{T, String}) where {T} = let
	input = e.input
	pos = e.position
	problem = e.problem
	if iszero(pos)
		IdentifierValError(IDENTIFIER_Malformed, "Malformed identifier: " * input * " " * problem)
	else
		pre = input[1:prevind(input, pos)]
		post = input[pos:end]
		pad = String(fill(UInt8(' '), sizeof(pre) + 3))
		IdentifierValError(IDENTIFIER_Malformed,
			"Malformed identifier:\n\n   " * pre * post * "\n" * pad * "└─╴" * problem)
	end
end

IdentifierValError(e::FastIdentifiers.ChecksumViolation{T, String}) where {T} = let
	input = string(e.id)
	pos = e.position
	problem = "expected " * string(e.expected) * ", got " * string(e.provided)
	if iszero(pos)
		IdentifierValError(IDENTIFIER_Checksum, "Checksum violation: " * input * " " * problem)
	else
		pre = input[1:prevind(input, pos)]
		post = input[pos:end]
		pad = String(fill(UInt8(' '), sizeof(pre) + 3))
		IdentifierValError(IDENTIFIER_Checksum,
			"Checksum violation:\n\n   " * pre * post * "\n" * pad * "└─╴" * problem)
	end
end


function OptParse.render_error(io::IO, err::IdentifierValError)

	if err.code == IDENTIFIER_Malformed
		print(io, err.msg)
	elseif err.code == IDENTIFIER_Checksum
		print(io, err.msg)
	elseif err.code == IDENTIFIER_OtherError
		print(io, "the identifier failed to parse for unknown reasons.")
	else
		print(io, "unreachable")
	end
end

struct IdentifierVal{T} <: AbstractValueParser{T, IdentifierValError}
	metavar::String
	identifier::Type{T}

	IdentifierVal(::Type{T}; metavar = "IDENT") where {T <: AbstractIdentifier} = new{T}(metavar, T)
end

(id::IdentifierVal{T})(input::String) where {T} = let
	maybeid = try
		parse(id.identifier, input)
	catch e

		# trimming really breaks here. Can't seem to get
		if e isa FastIdentifiers.MalformedIdentifier{T, String}
			return ParseResult{T, IdentifierValError}(Err(IdentifierValError(e)))
		elseif e isa FastIdentifiers.ChecksumViolation{T, String}
			return ParseResult{T, IdentifierValError}(Err(IdentifierValError(e)))
		else
			return ParseResult{T, IdentifierValError}(
				Err(IdentifierValError(IDENTIFIER_OtherError, ""))
			)
		end
	end

	return ParseResult{T, IdentifierValError}(Ok(maybeid))

end


OptParse.identifier(::Type{T}) where {T <: AbstractIdentifier} = IdentifierVal(T)
OptParse.identifier(meta::String, ::Type{T}) where {T <: AbstractIdentifier} = IdentifierVal(T; metavar = meta)


end
