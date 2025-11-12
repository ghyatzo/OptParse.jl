
# Value Parser interface


@kwdef struct StringVal
	metavar::String = "STRING"
	pattern::Regex = r".*"
end

(s::StringVal)(input::String)::Result{String, String} = let
	m = match(s.pattern, input)
	isnothing(m) && return Err("Expected a string matching pattern $(s.pattern), but got $input.")
	return Ok(input)
end

@kwdef struct Choice
	metavar::String = "CHOICE"
	caseInsensitive::Bool = true
	values::Vector{String}

	Choice(metavar, caseInsensitive, values::Vector{String}) = let
		normvals = caseInsensitive ? map(lowercase, values) : values
		new(metavar, caseInsensitive, normvals)
	end
end

(c::Choice)(input::String)::Result{String, String} = let
	norminput = x.caseInsensitive ? lowercase(input) : input
	index = findfirst(==(norminput), x.values)

	isnothing(index) && return Err("Expected of of $(join(x.values, ',')), but got $input")
	return Ok(x.values[index])
end


@wrapped struct ValueParser{T}
	union::Union{
		StringVal,
		Choice,
		Nothing
	}
end

hasvalue(v::ValueParser) = WrappedUnions.unwrap(v) !== nothing

parse(x::ValueParser, input::Base.String)::Result = @unionsplit parse(x, input)


valstring(;kw...) = ValueParser{String}(StringVal(;kw...))
choice(;kw...) = ValueParser{String}(Choice(;kw...))