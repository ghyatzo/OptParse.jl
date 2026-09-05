integerTypes = Data.SampledFrom([Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Int128, UInt128])
integers = @composed (I = integerTypes) -> Data.produce!(Data.Integers{I}())

text = Data.Satisfying(Data.Text(Data.AsciiCharacters(); max_len = 12), !startswith('-'))

bools = Data.Booleans()


abstract type ParserSpec end
abstract type OptionLikeSpec <: ParserSpec end

struct StringSpec <: ParserSpec
	allow_empty::Bool
end

struct IntegerSpec{T} <: ParserSpec end

struct OptionSpec <: OptionLikeSpec
	name::String
	value::ParserSpec
end

struct FlagSpec <: OptionLikeSpec
	name::String
end

abstract type ModifiedOptionSpec <: ParserSpec end

struct OptionalSpec <: ModifiedOptionSpec
    child::OptionSpec
end

struct DefaultSpec <: ModifiedOptionSpec
    child::OptionSpec
    fallback::Any
end

struct RepeatedSpec <: ModifiedOptionSpec
    child::OptionSpec
    min::Int
    max::Int
end

struct RecordSpec <: ParserSpec
	children::Vector{Pair{String, ParserSpec}}
end

rename(x::OptionLikeSpec, newname::String) = @set x.name = newname
function assign_names(x::OptionLikeSpec, counter)
    counter[] += 1
    return rename(x, "--opt$(counter[])")
end

assign_names(x::ModifiedOptionSpec, counter) = @set x.child = assign_names(x.child, counter)

assign_names(x::RecordSpec, counter = Ref(0)) = RecordSpec([
    field => assign_names(child, counter) for (field, child) in x.children
])

compile(x::StringSpec) = str(allow_empty = x.allow_empty)
compile(::IntegerSpec{T}) where {T} = integer(T)
compile(x::FlagSpec) = flag(x.name)
compile(x::OptionSpec) = option(x.name, compile(x.value))
compile(x::OptionalSpec) = optional(compile(x.child))
compile(x::DefaultSpec) = default(compile(x.child), x.fallback)
compile(x::RepeatedSpec) = repeated(compile(x.child); min = x.min, max = x.max)
compile(x::RecordSpec) = begin
	compiled = map(p -> Symbol(first(p)) => compile(last(p)), x.children)
	record(NamedTuple(compiled))
end

abstract type WitnessSpec end

struct ValueWitness <: WitnessSpec
	token::String
	expected::Any
end

struct FlagWitness <: WitnessSpec
	present::Bool
end

struct PresenceWitness <: WitnessSpec
    child::Union{Nothing, ValueWitness}
end

struct RepeatedWitness <: WitnessSpec
    children::Vector{ValueWitness}
end

struct RecordWitness <: WitnessSpec
	children::Vector{Pair{String, WitnessSpec}}
end


occurrences(x::FlagSpec, v::FlagWitness) = v.present ? [[x.name]] : Vector{String}[]
occurrences(x::OptionSpec, v::ValueWitness) = [[x.name, v.token]]
occurrences(x::Union{OptionalSpec, DefaultSpec}, v::PresenceWitness) =
    isnothing(v.child) ? Vector{String}[] : occurrences(x.child, v.child)
occurrences(x::RepeatedSpec, v::RepeatedWitness) = [[x.child.name, child.token] for child in v.children]

streams(x::ParserSpec, v::WitnessSpec) = [occurrences(x, v)]
streams(x::RecordSpec, v::RecordWitness) = reduce(vcat,
    (streams(s, w) for (s, w) in zip(last.(x.children), last.(v.children)));
    init = Vector{Vector{String}}[])

traversal_order(chunks) = [i for i in eachindex(chunks) for _ in eachindex(chunks[i])]

function render(case, order = traversal_order(streams(case.spec, case.witness)))
    chunks = streams(case.spec, case.witness)
    positions = ones(Int, length(chunks))
    argv = String[]
    for i in order
        i in eachindex(chunks) || throw(ArgumentError("Layout refers to an unknown stream"))
        positions[i] <= length(chunks[i]) || throw(ArgumentError("Layout exhausts a stream"))
        append!(argv, chunks[i][positions[i]])
        positions[i] += 1
    end
    all(positions .== length.(chunks) .+ 1) || throw(ArgumentError("Layout omits occurrences"))
    return argv
end

expected(::StringSpec, v::ValueWitness) = v.expected
expected(::IntegerSpec, v::ValueWitness) = v.expected
expected(::FlagSpec, v::FlagWitness) = v.present
expected(x::OptionSpec, v::ValueWitness) = v.expected
expected(x::OptionalSpec, v::PresenceWitness) =
    isnothing(v.child) ? nothing : expected(x.child, v.child)
expected(x::DefaultSpec, v::PresenceWitness) =
    isnothing(v.child) ? x.fallback : expected(x.child, v.child)
value_type(::StringSpec) = String
value_type(::IntegerSpec{T}) where {T} = T
expected(x::RepeatedSpec, v::RepeatedWitness) =
    value_type(x.child.value)[expected(x.child, child) for child in v.children]
expected(x::RecordSpec, v::RecordWitness) = NamedTuple([
	Symbol(f) => expected(s, w)
	for (f,s,w) in zip(first.(x.children), last.(x.children), last.(v.children))
])


str_gen = @composed (t = text) -> (spec=StringSpec(true), witness=ValueWitness(t, t))
int_gen = @composed (i = integers) -> (spec=IntegerSpec{typeof(i)}(), witness=ValueWitness(string(i), i))
val_gen = str_gen | int_gen


flag_gen = @composed (b = bools) -> (spec = FlagSpec(""), witness = FlagWitness(b))
option_gen = @composed (v = val_gen) -> (spec = OptionSpec("", v.spec), witness = v.witness)
value_witness(::StringSpec) = let token = Data.produce!(text)
    ValueWitness(token, token)
end
value_witness(::IntegerSpec{T}) where {T} = let value = Data.produce!(Data.Integers{T}())
    ValueWitness(string(value), value)
end

optional_gen = @composed (child = option_gen, present = bools) -> (
    spec = OptionalSpec(child.spec),
    witness = PresenceWitness(present ? child.witness : nothing),
)
default_gen = @composed (child = option_gen, present = bools) -> (
    spec = DefaultSpec(child.spec, value_witness(child.spec.value).expected),
    witness = PresenceWitness(present ? child.witness : nothing),
)
repeated_gen = @composed (child = option_gen, max_count = Data.Integers(0, 4)) -> begin
    min_count = Data.produce!(Data.Integers(0, max_count))
    count = Data.produce!(Data.Integers(min_count, max_count))
    (
        spec = RepeatedSpec(child.spec, min_count, max_count),
        witness = RepeatedWitness([value_witness(child.spec.value) for _ in 1:count]),
    )
end
primitive_gen = flag_gen | option_gen | optional_gen | default_gen | repeated_gen

function record_case(depth, leaf_budget, count = Data.produce!(Data.Integers(1, min(4, leaf_budget))))
    specs = Pair{String, ParserSpec}[]
    witnesses = Pair{String, WitnessSpec}[]
    remaining_budget = leaf_budget
    for i in 1:count
        # Reserve at least one leaf for each remaining sibling.
        child_budget = Data.produce!(Data.Integers(1, remaining_budget - (count - i)))
        nested = depth > 1 && Data.produce!(bools)
        child = nested ? record_case(depth - 1, child_budget) : Data.produce!(primitive_gen)
        push!(specs, "field$i" => child.spec)
        push!(witnesses, "field$i" => child.witness)
        remaining_budget -= child_budget
    end
    return (spec = RecordSpec(specs), witness = RecordWitness(witnesses))
end

record_gen = @composed (count = Data.Integers(1, 4)) -> begin
    case = record_case(3, 12, count)
    (spec = assign_names(case.spec), witness = case.witness)
end

ordered_record_gen = @composed (case = record_gen) -> begin
    remaining = length.(streams(case.spec, case.witness))
    active = findall(>(0), remaining)
    order = Int[]
    while !isempty(active)
        slot = Data.produce!(Data.Integers(1, length(active)))
        i = active[slot]
        push!(order, i)
        remaining[i] -= 1
        iszero(remaining[i]) && deleteat!(active, slot)
    end
    (; case..., order)
end


function valid_records(case)
    parser = compile(case.spec)
    wanted = expected(case.spec, case.witness)
    return all((render(case), render(case, case.order))) do argv
        result = tryoptparse(parser, argv)
        !is_error(result) && isequal(unwrap(result), wanted)
    end
end


