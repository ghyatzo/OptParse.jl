# These primitives implement the Parser Interface


# implement a simple primitive: the constant one
struct ArgConstant{T, TState}
	priority::Integer
	initialState::TState

	ArgConstant{T, T}(x::T) where {T} = new{T, T}(0, x)
end

parse(c::ArgConstant, context::ParserContext) = Ok(ParserSuccess(String[], context))
complete(c::ArgConstant, state) = state


struct ArgOption{T, TState}
	priority::Integer
	initialState::TState
	valueparser::ValueParser{T}

	names::Vector{String}

	# options
	description::String

	ArgOption{T, TState}(
		init_state::TState,
		valparser::ValueParser{T},
		names::Vector{String}
		;
		description=""
	) where {T, TState} = let
		new(10, init_state, valparser, names, description)
	end
end

state_t(::ArgOption{T, TState}) where {T, TState} = TState

ArgOption(names::Vector{String}; kw...) = let

	initialState::Result{Bool, String} = Ok(false)

	ArgOption{Bool, typeof(initialState)}(
		initialState,
		ValueParser{Bool}(nothing),
		names
		; kw...
	)
end

ArgOption(names::Vector{String}, val::ValueParser{T}; kw...) where {T} = let
	initialState::Result{T, String} = Err("Missing Option(s) $(names).")

	ArgOption{T, typeof(initialState)}(
		initialState,
		val,
		names
		; kw...
	)
end

_isduplicate(opt, context) = let
	!is_error(context.state) &&
	( hasvalue(opt.valueparser) || ErrorTypes.unwrap(context.state))
end

function parse(opt::ArgOption{T}, context::ParserContext{TState})::Result{ParserSuccess{TState}, ParserFailure} where {T, TState}

	if context.optionsTerminated
		return Err(ParserFailure(0, "No more options to be parsed."))
	elseif length(context.buffer) < 1
		return Err(ParserFailure(0, "Expected option got end of input."))
	end

	# When the input contains `--` is a signal to stop parsing options
	if (context.buffer[1] === "--")
		next = ParserContext{TState}(context.buffer[2:end], context.state, true)
		return Ok(ParserSuccess(context.buffer[1:1], next))
	end

	# when options are of the form `--option value` or `/O value`
	if context.buffer[1] in opt.names

		if _isduplicate(opt, context)
			return Err(ParserFailure(1, "$(context.buffer[1]) cannot be used multiple times"))
		end

		if !hasvalue(opt.valueparser)


			return Ok(ParserSuccess(
				context.buffer[1:1],

				ParserContext{TState}(
					context.buffer[2:end],
					Result{Bool,String}(Ok(true)),
					context.optionsTerminated
				)
			))
		end

		if length(context.buffer) < 2
			return Err(
				ParserFailure(
					1, "Option $(context.buffer[1]) requires a value, but got no value."
				)
			)
		end

		result = parse(opt.valueparser, context.buffer[2])

		return Ok(
			ParserSuccess(
				context.buffer[1:2],

				ParserContext{TState}(
					context.buffer[2:end],
					result,
					context.optionsTerminated
				)
			)
		)
	end

	# when options are of the form `--option=value` or `/O:value`
	prefixes = filter(opt.names) do name
		startswith(name, "--") || startswith(name, "/")
	end
	map!(prefixes) do name
		startswith(name, "/") ? "$name:" : "$name="
	end
	for prefix in prefixes
		startswith(context.buffer[1], prefix) || continue

		if _isduplicate(opt, context)
			return Err(ParserFailure(1, "$(prefix[1:end-1]) cannot be used multiple times"))
		end

		value = context.buffer[1][length(prefix)+1:end]

		if !hasvalue(opt.valueparser)
			return Err(ParserFailure(
				1,
				"Option $(prefix[1:end-1]) is a Boolean flat, but got a value: $value."
			))
		end

		result = parse(opt.valueparser, value)
		return Ok(
			ParserSuccess(
				context.buffer[1:2],

				ParserContext{TState}(
					context.buffer[2:end],
					result,
					context.optionsTerminated
				)
			)
		)

	end

	if !hasvalue(opt.valueparser)
		# When the input contains bundled options: -abc

		short_options = filter(opt.names) do name
			match(r"^-[^-]$", name) !== nothing
		end

		for short_opt in short_options
			startswith(context.buffer[1], short_opt) || continue

			if _isduplicate(opt, context)
				return Err(ParserFailure(1, "Option $(short_opt) cannot be used multiple times"))
			end

			return Ok(
				ParserSuccess(
					context.buffer[1][1:2],

					ParserContext(
						["-$(context.buffer[1][3:end])", context.buffer[2:end]...],
						Result{Bool,String}(Ok(true)),
						context.optionsTerminated
					)
				)
			)
		end

	end

	return Err(ParserFailure(
		0, "No Matched option for $(context.buffer[1])"
	))
end

function complete(opt::ArgOption{T, TState}, state)::Result{T, String} where {T, TState}
	if isnothing(state)
		return hasvalue(opt.valueparser) ? Ok(false) : Err("Missing option $(opt.names).")
	end

	!is_error(state) && return state
	error = unwrap_error(state)
	return Err("$(opt.names): $error")
end




@wrapped struct Parser{T, TState}
	union::Union{
		ArgConstant,
		ArgOption,
	}
end

Base.getproperty(p::Parser, field::Symbol) = @unionsplit Base.getproperty(p, field)
parse(p::Parser, context::ParserContext)::ParserResult = @unionsplit parse(p, context)
complete(p::Parser, state) = @unionsplit complete(p, state)

option(names::Vector{String}, val::ValueParser{T}; kw...) where {T} = let
	argopt = ArgOption(names, val)

	Parser{T, state(argopt)}(argopt)
end