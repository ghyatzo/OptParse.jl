@enum ListValErrCode::UInt8 begin
	LIST_TooMany
	LIST_TooFew
end

struct ListValError <: AbstractParseError
	code::ListValErrCode
	num::Int
	got::String
end

function render_error(io::IO, err::ListValError)
	return if err.code == LIST_TooFew
		print(io, "Too few items in the list, expected at least $(err.num), got $(err.got)")
	elseif err.code == LIST_TooMany
		print(io, "Too many items in the list, expected at most $(err.num), got $(err.got)")
	else
		@assert false "unreachable"
	end
end

struct ListVal{T, E, P} <: AbstractValueParser{T, E}
	metavar::String
	nelements::Int
	separator::Char
	subparsers::P

	ListVal(valparser::AbstractValueParser, num::Int; metavar = "LIST", separator=',') = let
		separator == ' ' && throw(ArgumentError("Can't use space as a separator."))
		subparsers = ntuple(_ -> valparser, num)
		T = Tuple{map(val_t, subparsers)...}
		E = Union{err_t(valparser), ListValError}
		new{T, E, typeof(subparsers)}(metavar, num, separator, subparsers)
	end

	ListVal(valparsers...; metavar = "LIST", separator=',') = let
		separator == ' ' && throw(ArgumentError("Can't use space as a separator."))
		types = map(val_t, valparsers)
		E = Union{map(err_t, valparsers)..., ListValError}
		new{Tuple{types...}, E, typeof(valparsers)}(metavar, length(types), separator, valparsers)
	end
end

(l::ListVal{T, E, P})(input::AbstractString) where {T, E, P} = let
	vals = split(input, l.separator)

	if length(vals) < length(l.subparsers)
		return Result{T, E}'.Err(
			ListValError(LIST_TooFew, l.nelements, "$(length(vals))")
		)
	elseif length(vals) > length(l.subparsers)
		return Result{T, E}'.Err(
			ListValError(LIST_TooMany, l.nelements, "$(length(vals))")
		)
	end

	results = ntuple(i -> l.subparsers[i](vals[i]), Val(fieldcount(P)))
	errid = findfirst(is_error, results)

	if !isnothing(errid)
		err = unwrap_error(results[errid])
		return Result{T, E}'.Err(err)
	end

	values = map(unwrap, results)

	return Result{T, E}'.Ok(values)
end
