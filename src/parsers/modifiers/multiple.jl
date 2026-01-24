const MultipleState{X} = Vector{X}

struct ModMultiple{T, S, _p, P} <: AbstractParser{T, S, _p, P}
	initialState::S
	parser::P
	#
	min::Int
	max::Int
end

ModMultiple(parser::P; min::Integer = 0, max::Integer = typemax(Int)) where {P <: AbstractParser} = let
	ModMultiple{
		Vector{tval(P)},
		MultipleState{tstate(P)},
		priority(P),
		P
	}(tstate(P)[], parser, min, max)
end

function parse(p::ModMultiple{T,MultipleState{S}}, ctx::Context{MultipleState{S}})::ParseResult{MultipleState{S}, String} where {T, S}

	#=If the state is empty, it means that we're adding a new match.=#
	hasadded = isempty(ℒ_state(ctx))

	#=With a non empty state, pass in the latest state to the parser that maybe needs to keep parsing.=#
	child_state = isempty(ℒ_state(ctx)) ? p.parser.initialState : ℒ_state(ctx)[end]
	child_ctx = widen_restate(S, ctx, child_state)
	result = parse(unwrapunion(p.parser), child_ctx)::ParseResult{S, String}

	if is_error(result)
		if !hasadded
			#=There has been an error from the internal parser.
			It can mean that it has finished consuming its pattern.
			Erase its memory and try again from a blank slate. Maybe the pattern repeats.=#
			child_state = p.parser.initialState
			child_ctx = widen_restate(S, ctx, child_state)
			result = parse(unwrapunion(p.parser), child_ctx)::ParseResult{S, String}

			if is_error(result)
				#=The error is real, return it.=#
				return parseerr(unwrap_error(result))
			end

			#=Otherwise, we've encountered a new repetition. Add it to the state.=#
			hasadded = true
		else
			return parseerr(unwrap_error(result))
		end
	end

	parse_ok = unwrap(result)
	#=If the parent parser encounters a new repetition, add it at the end of the state.
	Otherwise, update the last state with the latest result from the child parser.=#
	nextst = hasadded ? deepcopy(ℒ_state(ctx)) : deepcopy(ℒ_state(ctx)[1:end-1])
	push!(nextst, ℒ_nextstate(parse_ok))

	nextctx = widen_restate(MultipleState{S}, ℒ_nextctx(parse_ok), nextst)
	return parseok(nextctx, ℒ_consumed(parse_ok))

end

function complete(p::ModMultiple{T, MultipleState{S}, _p, P}, state::MultipleState{S})::Result{T, String} where {T,S, _p, P}
	result = tval(P)[]
	for s in state
		val = @? complete(unwrapunion(p.parser), s)
		push!(result, val)
	end

	if length(result) < p.min
		return Err("Expected at least $(p.min) values, but got only $(length(result)).")
	elseif length(result) > p.max
		return Err("Expected at most $(p.max) values, but got $(length(result)).")
	end

	return Ok(result)

end