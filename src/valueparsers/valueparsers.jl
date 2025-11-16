
# Value Parser interface
# struct _ValueParser{T}
# 	metavar::String
# 	# ... custom vars
# end

# function parse end # String -> Result{T, String}
# function format end # T -> String


@kwdef struct StringVal{T}
	metavar::String = "STRING"
	pattern::Regex = r".*"
end

(s::StringVal)(input::String)::Result{String, String} = let
	m = match(s.pattern, input)
	isnothing(m) && return Err("Expected a string matching pattern $(s.pattern), but got $input.")
	return Ok(input)
end

@kwdef struct Choice{T}
	metavar::String = "CHOICE"
	caseInsensitive::Bool = true
	values::Vector{T}

	Choice(metavar, caseInsensitive, values::Vector{T}) where {T} = let
		normvals = caseInsensitive ? map(lowercase, values) : values
		new{T}(metavar, caseInsensitive, normvals)
	end
end

(c::Choice)(input::String)::Result{String, String}= let
	norminput = c.caseInsensitive ? lowercase(input) : input
	index = findfirst(==(norminput), c.values)

	isnothing(index) && return Err("Expected of of $(join(c.values, ',')), but got $input")
	return Ok(c.values[index])
end

@kwdef struct IntegerVal{T}
	metaval::String = "INTEGER"
	#
	type::Type = T
	min::Union{Int, Nothing} = nothing
	max::Union{Int, Nothing} = nothing
end
((iv::IntegerVal{T})(input::String)::Result{T, String}) where {T} = let
	val = tryparse(T, input)
	if isnothing(val)
		return Err("Expected valid integer, got `$input`")
	end

	(!isnothing(iv.min) && val < iv.min) && return Err("Value $input is below the minimum: $(iv.min)")
	(!isnothing(iv.max) && val > iv.max) && return Err("Value $input is above the maximum: $(iv.max)")

	return Ok(val)
end


@wrapped struct ValueParser{T}
	union::Union{
		StringVal{T},
		IntegerVal{T},
		Choice{T}
	}
end

(parse(x::ValueParser{T}, input::String)::Result{T, String}) where {T} = @unionsplit parse(x, input)
((v::ValueParser{T})(input::String)::Result{T, String}) where {T} = @unionsplit v(input)


str(;kw...) = ValueParser{String}(StringVal{String}(;kw...))
choice(values::Vector{T};kw...) where {T} = ValueParser{T}(Choice(;values, kw...))
integer(::Type{T}; kw...) where {T} = ValueParser{T}(IntegerVal{T}(;type=T, kw...))
integer(;kw...) = ValueParser{Int}(IntegerVal{Int}(;kw...))