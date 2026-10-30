@enum PairValErrCode::UInt8 begin
	PAIR_TooFew
	PAIR_TooMany
end

struct PairValError <: AbstractParseError
	code::PairValErrCode
	got::String
end

function render_error(io::IO, err::PairValError)
	return if err.code == PAIR_TooFew
		print(io, "Too few items in the pair, expected 2, got $(err.got)")
	elseif err.code == PAIR_TooMany
		print(io, "Too many items in the pair, expected 2, got $(err.got)")
	else
		@assert false "unreachable"
	end
end

struct PairVal{T, E, P} <: AbstractValueParser{T, E}
	metavar::String
	separator::Char
	subparsers::P

	PairVal(first, second; metavar = nothing, separator='=') = let
		separator == ' ' && throw(ArgumentError("Can't use space as a separator."))
		valparsers = (first, second)
		E = Union{err_t(first), err_t(second), PairValError}

		metavar = @something metavar "$(OptParse.metavar(first))$separator$(OptParse.metavar(second))"

		new{Pair{val_t(first), val_t(second)}, E, typeof(valparsers)}(metavar, separator, valparsers)
	end
end

(p::PairVal{T, E, P})(input::AbstractString) where {T, E, P} = let
	vals = split(input, p.separator)

	if length(vals) < 2
		return Result{T, E}'.Err(PairValError(PAIR_TooFew, "$(length(vals))"))
	elseif length(vals) > 2
		return Result{T, E}'.Err(PairValError(PAIR_TooMany, "$(length(vals))"))
	end

	results = ntuple(i -> p.subparsers[i](vals[i]), Val(2))
	errid = findfirst(is_error, results)

	if !isnothing(errid)
		err = unwrap_error(results[errid])
		return Result{T, E}'.Err(err)
	end

	values = map(unwrap, results)

	return Result{T, E}'.Ok(values[1] => values[2])
end
