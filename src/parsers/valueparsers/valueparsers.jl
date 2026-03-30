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
include("path.jl")


@wrapped struct ValueParser{T}
    union::Union{
        StringVal{T},
        IntegerVal{T},
        FloatVal{T},
        Choice{T},
        UUIDVal{T},
        PathVal{T}
    }
end

Base.getproperty(v::ValueParser, f::Symbol) = @unionsplit Base.getproperty(v, f)

metavar(v::ValueParser) = v.metavar
trymetavar(v::ValueParser) = isempty(metavar(v)) ? default_metavar(unwrapunion(v)) : metavar(v)

((v::ValueParser{T})(input::String)::ParseResult{T}) where {T} = @unionsplit v(input)

str(; kw...) = ValueParser{String}(StringVal{String}(; kw...))
str(meta::AbstractString; kw...) = ValueParser{String}(StringVal{String}(; metavar = String(meta), kw...))

choice(values::AbstractVector{<:AbstractString}; kw...) = ValueParser{String}(Choice(String.(values); kw...))
choice(metavar::AbstractString, values::AbstractVector{<:AbstractString}; kw...) =
    ValueParser{String}(Choice(String.(values); metavar = String(metavar), kw...))
choice(::Type{AnEnum}; kw...) where {AnEnum <: Enum} = ValueParser{AnEnum}(Choice(AnEnum; kw...))
choice(metavar::AbstractString, ::Type{AnEnum}; kw...) where {AnEnum <: Enum} =
    ValueParser{AnEnum}(Choice(AnEnum; metavar = String(metavar), kw...))

integer(::Type{T}; kw...) where {T <: Integer} = ValueParser{T}(IntegerVal{T}(; type = T, kw...))
integer(metavar::AbstractString, ::Type{T}; kw...) where {T <: Integer} =
    ValueParser{T}(IntegerVal{T}(; metavar = String(metavar), type = T, kw...))
integer(; kw...) = ValueParser{Int}(IntegerVal{Int}(; kw...))
integer(metavar::AbstractString; kw...) = ValueParser{Int}(IntegerVal{Int}(; metavar = String(metavar), kw...))
i8(; kw...) = integer(Int8; kw...)
i8(metavar::AbstractString; kw...) = integer(metavar, Int8; kw...)
i16(; kw...) = integer(Int16; kw...)
i16(metavar::AbstractString; kw...) = integer(metavar, Int16; kw...)
i32(; kw...) = integer(Int32; kw...)
i32(metavar::AbstractString; kw...) = integer(metavar, Int32; kw...)
i64(; kw...) = integer(Int64; kw...)
i64(metavar::AbstractString; kw...) = integer(metavar, Int64; kw...)
u8(; kw...) = integer(UInt8; kw...)
u8(metavar::AbstractString; kw...) = integer(metavar, UInt8; kw...)
u16(; kw...) = integer(UInt16; kw...)
u16(metavar::AbstractString; kw...) = integer(metavar, UInt16; kw...)
u32(; kw...) = integer(UInt32; kw...)
u32(metavar::AbstractString; kw...) = integer(metavar, UInt32; kw...)
u64(; kw...) = integer(UInt64; kw...)
u64(metavar::AbstractString; kw...) = integer(metavar, UInt64; kw...)

flt(::Type{T}; kw...) where {T} = ValueParser{T}(FloatVal{T}(; type = T, kw...))
flt(metavar::AbstractString, ::Type{T}; kw...) where {T} =
    ValueParser{T}(FloatVal{T}(; metavar = String(metavar), type = T, kw...))
flt(; kw...) = flt64(; kw...)
flt(metavar::AbstractString; kw...) = flt64(metavar; kw...)
flt32(; kw...) = flt(Float32; kw...)
flt32(metavar::AbstractString; kw...) = flt(metavar, Float32; kw...)
flt64(; kw...) = flt(Float64; kw...)
flt64(metavar::AbstractString; kw...) = flt(metavar, Float64; kw...)

uuid(; kw...) = ValueParser{UUID}(UUIDVal{UUID}(; kw...))
uuid(metavar::AbstractString; kw...) = ValueParser{UUID}(UUIDVal{UUID}(; metavar = String(metavar), kw...))

path(; kw...) = ValueParser{String}(PathVal{String}(; kw...))
path(metavar::AbstractString; kw...) = ValueParser{String}(PathVal{String}(; metavar = String(metavar), kw...))
