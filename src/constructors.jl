struct Object{T, S, p, P}
	initialState::S # NamedTuple of the states of its parsers
	#
	parsers::P
	label::String
end

Object{T,S}(priority, initialState, parsers::P, label) where {T, S, P} =
	Object{T, S, priority, P}(initialState, parsers, label)

# object(label ;
# 	option = option("--option", string()),
# 	flag = flag("--version")
# )
_extract_parser_info(obj::T) where {T} = let
	labels = fieldnames(T)
	parsers_t = fieldtypes(T)
	parsers = values(obj)
	parsers_tvals = map(tval, parsers_t)
	parsers_tstates = map(tstate, parsers_t)
	priorities = map(priority, parsers_t)

	#= We need to sort only the first element to maintain typestability =#
	bags = sort(map(Tuple, zip(priorities, labels, parsers_t, parsers)), rev=true, lt=((t1,t2)) -> t1[1] < t2[1])
	slabels = ntuple(length(labels)) do i; bags[i][2] end
	sparsers_t = ntuple(length(labels)) do i; bags[i][3] end
	# sparsers = ntuple(length(labels)) do i; bags[i][4] end

	# @show bags

	obj_t = NamedTuple{slabels, Tuple{parsers_tvals...}}
	obj_tstates = NamedTuple{slabels, Tuple{parsers_tstates...}}

	prio = maximum(priorities)
	init_state = NamedTuple{slabels}(map(p->getproperty(p, :initialState), sparsers))

	slabels, sparsers, obj_t, obj_tstates, prio, init_state
end


function parse(p::Object{T, S}, ctx::Context)::ParseResult{S, String} where {T, S}

	error = ParseFailure(0, "Expected argument, option or command, but got end of input.")

	labels = fieldnames(T)
	@assert length(labels) == length(p.parsers)

	#= greedy parsing trying to consume as many field as possible =#
	current_ctx = ctx
	any_success = false

	all_consumed = String[]

	#= keep trying to parse fields until no more can be matched =#
	made_progress = true
	while (made_progress && length(ctx.buffer) > 0)
		made_progress = false

		for (field, child_parser) in zip(labels, p.parsers)
			child_parser_state = isnothing(current_ctx.state) || field ∉ keys(current_ctx.state) ?
				p.initialState[field] : current_ctx.state[field]

			child_parser_ctx = Context(
				current_ctx.buffer,
				child_parser_state,
				current_ctx.optionsTerminated
			)

			result = @unionsplit parse(child_parser, child_parser_ctx)
			if !is_error(result)
				parse_ok = ErrorTypes.unwrap(result)

				if length(parse_ok.consumed) > 0
					newstate = merge(current_ctx.state, NamedTuple{(field,)}((parse_ok.next.state,)))

					current_ctx = Context(
						parse_ok.next.buffer,
						newstate,
						parse_ok.next.optionsTerminated
					)
					append!(all_consumed, parse_ok.consumed)
					any_success = true
					made_progress = true
					break #= restart the field loop with an updated state =#
				end

			elseif is_error(result)
				parse_err = unwrap_error(result)
				if error.consumed < parse_err.consumed
					error = parse_err
				end
			end
		end

		if any_success
			return Ok(ParseSuccess(
				all_consumed,
				current_ctx
			))
		end

		#= if buffer is empty and no parser consumed input, check if all parsers can complete =#
		if length(ctx.buffer) == 0
			all_can_complete = true

			for (field, child_parser) in zip(labels, p.parsers)
				field_state = isnothing(ctx.state) || field ∉ keys(ctx.state) ? p.initialState[field] : ctx.state[field]

				complete_result = complete(child_parser, field_state)

				if is_error(complete_result)
					all_can_complete = false
					break
				end

				if all_can_complete
					return Ok(ParseSuccess([], ctx))
				end
			end
		end

		return Err(error)
	end
end

function complete(p::Object{T}, st::S)::Result{T, String} where {T, S}
	objlabels = fieldnames(T)
	objtypes = fieldtypes(T)

	_results = (;)
	# the state will be a named tuple
	@assert st isa NamedTuple
	for field in keys(st)
		fieldid = findfirst(==(field), objlabels)
		isnothing(fieldid) && continue # not present

		field_t = objtypes[fieldid]
		child_parser = p.parsers[fieldid]
		result = @unionsplit complete(child_parser, st[field])

		if !is_error(result)
			value = ErrorTypes.unwrap(result)::field_t

			_results = merge(_results, NamedTuple{(field,)}((value,)))
		else
			return Err(unwrap_error(result))
		end
	end
	@assert _results isa T

	return Ok(_results)
end

