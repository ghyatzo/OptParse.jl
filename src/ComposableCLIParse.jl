module ComposableCLIParse

using WrappedUnions
using ErrorTypes

# based on: https://optique.dev/concepts

# primitive parsers: building blocks of command line interfaces
#	- constant()
#	- option()
#	- flag()
#	- argument()
#	- command()
#	- parsers priority: command > argument > option/flag > constant


# value parsers: specialized components that convert raw string into desired outputs
#	- string(pattern)
#	- integer(min, max, type)
#	- float(min, max, allowInfinity, allowNan)
#	- choice([list of choices], caseinsensitive)
#	- uri()
#	- uuid()
#	- path()
#	- instant() # moment in time
#	- duration()
#	- zone-datetime()
#	- date()
#	- time()
#	- datetime()
#	- yearmonth()
#	- monthday()
#	- timezone()
#	- custom value parser:
#		Interface ValueParser{T}:
#			must have a metavar keyword arg
#			a parse function String -> ParseResult{T}
#			a format function T -> String


# modifying combinators: Transform existing Parsers adding additional behaviour on top of the core one
#	- optional()
#	- withDefault()
#	- map()
#	- multiple(min, max) (match multiple times, collect into an array.)
#	-

# construct combinators: combine different parsers into new ones
# 	- object(), combines multiple named parsers into a single parser that produces a single object
#	- tuple(), combines parsers to produce tuple of results. preserves order.
#	- or(), mutually exclusive alternatives
#	- merge(), takes two parsers and generate a new single parser combining both
#	- concat(), appends tuple parsers
#	- longest-match(), tries all parses and selects the one with the longest match.
#	- group(), documentation only combinator, adds a group label to parsers inside.
function map_err(f, ::Type{E}, x::Result{O})::Result{O, E} where {O, E}
	data = x.x
	return Result{O, E}(data isa Ok ? Ok(data.x) : Err(f(data.x)))
end






include("parser.jl")

# struct _ValueParser{T}
# 	metavar::String
# 	# ... custom vars
# end

# function parse end # String -> Result{T, String}
# function format end # T -> String

include("valueparsers.jl")


include("primitives.jl")



#####
# entry point
function parse(parser::Parser{T, TState}, args::Vector{String})::Result{T, String} where {T, TState}

	context = ParserContext(
		args,
		parser.initialState,
		false
	)

	while true
		mayberesult = parse(parser, context)::ParserResult{TState}

		is_error(mayberesult) && return Err(unwrap_error(mayberesult).error)
		result = ErrorTypes.unwrap(mayberesult)

		previous_buffer = context.buffer
		context = result.next

		if ( length(context.buffer) > 0 &&
			 length(context.buffer) == length(previous_buffer) &&
			 context.buffer[0] === previous_buffer[0])

			return Err("Unexpected option or argument: $(context.buffer[0]).")
		end

		length(context.buffer) > 0 || break
	end

	endResult = complete(parser, context.state)
end


end # module ComposableCLIParse
