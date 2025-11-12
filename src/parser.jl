
struct ParserContext{T}
	buffer::Vector{String}
	state::T
	optionsTerminated::Bool
end


struct ParserSuccess{T}
	consumed::Vector{String}
	next::ParserContext{T}
end

struct ParserFailure
	consumed::Integer
	error::String
end

const ParserResult{T} = Result{ParserSuccess{T}, ParserFailure}
# parser interface,
# all objects and funciton will always return a parser!
# struct _Parser{TValue, TState}
# 	priority::Integer
# 	initialState::TState

# 	# ... extra stuff
# end

# function parse end # ParserContext -> ::Result{ParseSuccess, ParseFailure}

# function complete end # TState -> ::Result{TValue, ValueFailure}

# function gethelp end
