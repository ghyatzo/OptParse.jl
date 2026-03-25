# Value Parser interface
# struct ValueParser{T}
# 	metavar::String
# 	# ... custom vars
# end

# function parse end # String -> ParseResult{T}
# function format end # T -> String


include("string.jl")
include("choice.jl")
include("integer.jl")
include("float.jl")
include("uuid.jl")


@wrapped struct ValueParser{T}
    union::Union{
        StringVal{T},
        IntegerVal{T},
        FloatVal{T},
        Choice{T},
        UUIDVal{T},
    }
end

Base.getproperty(v::ValueParser, f::Symbol) = @unionsplit Base.getproperty(v, f)
metavar(v::ValueParser) = v.metavar

trymetavar(v::ValueParser) = isempty(metavar(v)) ? default_metavar(unwrapunion(v)) : metavar(v)

# (parse(x::ValueParser{T}, input::String)::ParseResult{T}) where {T} = @unionsplit parse(x, input)
((v::ValueParser{T})(input::String)::ParseResult{T}) where {T} = @unionsplit v(input)


str(; kw...) = ValueParser{String}(StringVal{String}(; kw...))
choice(values::Vector{T}; kw...) where {T} = ValueParser{T}(Choice(; values, kw...))
integer(::Type{T}; kw...) where {T <: Integer} = ValueParser{T}(IntegerVal{T}(; type = T, kw...))
integer(; kw...) = ValueParser{Int}(IntegerVal{Int}(; kw...))
i8(; kw...) = integer(Int8, ; kw...)
i16(; kw...) = integer(Int16, ; kw...)
i32(; kw...) = integer(Int32, ; kw...)
i64(; kw...) = integer(Int64, ; kw...)
u8(; kw...) = integer(UInt8, ; kw...)
u16(; kw...) = integer(UInt16, ; kw...)
u32(; kw...) = integer(UInt32, ; kw...)
u64(; kw...) = integer(UInt64, ; kw...)

flt(::Type{T}; kw...) where {T} = ValueParser{T}(FloatVal{T}(; type = T, kw...))
flt(; kw...) = flt64(; kw...)
flt32(; kw...) = flt(Float32; kw...)
flt64(; kw...) = flt(Float64; kw...)

uuid(; kw...) = ValueParser{UUID}(UUIDVal{UUID}(; kw...))
