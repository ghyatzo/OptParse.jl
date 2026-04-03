Base.show(io::IO, p::Parser) = @unionsplit show_compact(io, p)
Base.show(io::IO, v::ValueParser) = @unionsplit show_compact(io, v)
Base.show(io::IO, ::MIME"text/plain", p::Parser) = @unionsplit show_pretty(io, p, 0)
Base.show(io::IO, ::MIME"text/plain", v::ValueParser) = @unionsplit show_pretty(io, v, 0)

function _print_indent(io::IO, indent::Int)
	for _ in 1:indent
		print(io, "  ")
	end
end

show_compact(io::IO, p::Parser) = @unionsplit show_compact(io, p)
show_compact(io::IO, v::ValueParser) = @unionsplit show_compact(io, v)

show_compact(io::IO, p::Choice) = let
	print(io, "choice(")
	print(io, join(string.(p.values), '|'))
	if !isempty(p.metavar)
		print(io, ",", p.metavar)
	end
	print(io, ")")
end
show_compact(io::IO, p::StringVal) = let
	print(io, "str(")
	if !isempty(p.metavar)
		print(io, p.metavar)
	end
	print(io, ")")
end
show_compact(io::IO, p::IntegerVal) = let
	print(io, "integer(")
	if !isnothing(p.min) || !isnothing(p.max)

		lb = isnothing(p.min) ? "" : "$(p.min)"
		ub = isnothing(p.max) ? "" : "$(p.max)"

		print(io, "$lb..$ub")
	end
	if !isempty(p.metavar)
		if !isnothing(p.min) || !isnothing(p.max)
			print(io, ",")
		end
		print(io, p.metavar)
	end
	print(io, ")")
end
show_compact(io::IO, p::FloatVal) = let
	print(io, "flt(")
	if !isnothing(p.min) || !isnothing(p.max)

		lb = isnothing(p.min) ? "" : "$(p.min)"
		ub = isnothing(p.max) ? "" : "$(p.max)"

		print(io, "$lb..$ub")
	end
	if !isempty(p.metavar)
		if !isnothing(p.min) || !isnothing(p.max)
			print(io, ",")
		end
		print(io, p.metavar)
	end
	print(io, ")")
end
show_compact(io::IO, p::UUIDVal) = let
	print(io, "uuid(")
	if !isempty(p.allowedVersions)
		print(io, join(p.allowedVersions, '|'))
	end
	if !isempty(p.metavar)
		if !isempty(p.allowedVersions)
			print(io, ",")
		end
		print(io, p.metavar)
	end
	print(io, ")")
end

show_compact(io::IO, p::ArgGate) = let
	print(io, "gate(")
	print(io, join(p.names, ", "))
	print(io, ")")
end
show_compact(io::IO, p::ArgOption) = let
	print(io, "option(")
	print(io, join(p.names, ", "))
	print(io, ", ")
	show_compact(io, p.valparser)
	print(io, ")")
end
val(::Val{x}) where {x} = x
show_compact(io::IO, p::ArgConstant) = let
	print(io, "@constant(")
	print(io, val(p.initialState))
	print(io, ")")
end
show_compact(io::IO, p::ArgArgument) = let
	print(io, "arg(")
	if !isempty(metavar(p.valparser))
		print(io, metavar(p.valparser))
	else
		show_compact(io, p.valparser)
	end
	print(io, ")")
end
show_compact(io::IO, p::ArgCommand) = let
	print(io, "command(")
	print(io, p.names[1])
	print(io, ")")
end

show_compact(io::IO, p::ConstrObject) = let
	print(io, "object(")
	print(io, join(string.(keys(p.parsers)), ", "))
	print(io, ")")
end
show_compact(io::IO, p::ConstrOr) = let
	print(io, "or(")
	print(io, length(p.parsers))
	print(io, " branches)")
end
show_compact(io::IO, p::ConstrTuple) = let
	print(io, "sequence(")
	print(io, length(p.parsers))
	print(io, " items)")
end

function _show_optional_flag(io::IO, p::ModWithDefault)
	inner = unwrapunion(p.parser)
	if p.default === false && inner isa ArgGate
		print(io, "flag(")
		print(io, join(inner.names, ", "))
		print(io, ")")
		return true
	end
	return false
end

show_compact(io::IO, p::ModWithDefault) = let
	if _show_optional_flag(io, p)
		return
	end
	print(io, "default(")
	show_compact(io, p.parser)
	print(io, ", ")
	show(io, p.default)
	print(io, ")")
end
show_compact(io::IO, p::ModMultiple) = let
	print(io, "multiple(")
	if p.min != 0 || p.max != typemax(Int)
		lb = p.min == 0 ? "" : "$(p.min)"
		ub = p.max == typemax(Int) ? "" : "$(p.max)"
		print(io, "$lb..$ub, ")
	end
	show_compact(io, p.parser)
	print(io, ")")
end

show_pretty(io::IO, p::Parser, ident::Int = 0) = @unionsplit show_pretty(io, p)
show_pretty(io::IO, v::ValueParser, ident::Int = 0) = @unionsplit show_pretty(io, v)
show_pretty(io::IO, p::Choice, indent::Int = 0) = show_compact(io, p)
show_pretty(io::IO, p::StringVal, indent::Int = 0) = show_compact(io, p)
show_pretty(io::IO, p::IntegerVal, indent::Int = 0) = show_compact(io, p)
show_pretty(io::IO, p::FloatVal, indent::Int = 0) = show_compact(io, p)
show_pretty(io::IO, p::UUIDVal, indent::Int = 0) = show_compact(io, p)

show_pretty(io::IO, p::ArgGate, indent::Int = 0) = show_compact(io, p)
show_pretty(io::IO, p::ArgOption, indent::Int = 0) = show_compact(io, p)
show_pretty(io::IO, p::ArgConstant, indent::Int = 0) = show_compact(io, p)
show_pretty(io::IO, p::ArgArgument, indent::Int = 0) = show_compact(io, p)

show_pretty_after_prefix(io::IO, p, indent::Int) = @unionsplit show_compact(io, p)

function show_pretty_after_prefix(io::IO, p::ArgCommand, indent::Int)
	show_compact(io, p)
	print(io, "\n")
	_print_indent(io, indent + 1)
	show_pretty(io, p.parser, indent + 1)
end

show_pretty(io::IO, p::ArgCommand, indent::Int = 0) = show_pretty_after_prefix(io, p, indent)

function show_pretty(io::IO, p::ConstrObject, indent::Int = 0)
	print(io, "object")
	for (field, child) in pairs(p.parsers)
		print(io, "\n")
		_print_indent(io, indent + 1)
		print(io, field, ": ")
		show_pretty_after_prefix(io, child, indent + 1)
	end
end

function show_pretty(io::IO, p::ConstrOr, indent::Int = 0)
	print(io, "or")
	for (i, child) in enumerate(p.parsers)
		print(io, "\n")
		_print_indent(io, indent + 1)
		print(io, i, ": ")
		show_pretty_after_prefix(io, child, indent + 1)
	end
end

function show_pretty(io::IO, p::ConstrTuple, indent::Int = 0)
	print(io, "sequence")
	for (i, child) in enumerate(p.parsers)
		print(io, "\n")
		_print_indent(io, indent + 1)
		print(io, i, ": ")
		show_pretty_after_prefix(io, child, indent + 1)
	end
end

show_pretty(io::IO, p::ModWithDefault, indent::Int = 0) = show_compact(io, p)
show_pretty(io::IO, p::ModMultiple, indent::Int = 0) = show_compact(io, p)
