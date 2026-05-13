# Value Parser interface
# struct SomeValueParser{T} <: AbstractValueParser{T}
# 	metavar::String
# 	# ... custom vars
# end

# function parse end # String -> ParseResult{T}
# function format end # T -> String

abstract type AbstractValueParser{T} end

metavar(v::AbstractValueParser) = v.metavar
trymetavar(v::AbstractValueParser) = isempty(metavar(v)) ? default_metavar(v) : metavar(v)

((v::AbstractValueParser{T})(input::String)::ParseResult{T}) where {T} = tryparse(v, input)


include("string.jl")
include("choice.jl")
include("integer.jl")
include("float.jl")
include("uuid.jl")
include("path.jl")

"""
    str(; kw...)
    str(metavar::AbstractString; kw...)

String value parser.

Accepts any string by default, optionally constrained by a regular expression.

# Keywords
- `pattern::Regex = r".*"`: regular expression the input must match
- `allow_empty::Bool = false`: whether the empty string is accepted
- `metavar::String`: placeholder used in usage/help output

# Examples
```jldoctest
julia> using OptParse

julia> name = str("NAME");

julia> optparse(arg(name), ["alice"])
"alice"

julia> txt = str("FILE"; pattern = r".*\\.(txt|md)\$");

julia> optparse(arg(txt), ["readme.md"])
"readme.md"

julia> empty_ok = str("VALUE"; allow_empty = true);

julia> optparse(arg(empty_ok), [""])
""
```

# See Also
- [`arg`](@ref): consume a positional value using this parser
- [`option`](@ref): consume an option value using this parser
"""
str(; kw...) = StringVal{String}(; kw...)
str(meta::AbstractString; kw...) = StringVal{String}(; metavar = String(meta), kw...)

"""
    choice(values::AbstractVector{<:AbstractString}; kw...)
    choice(metavar::AbstractString, values::AbstractVector{<:AbstractString}; kw...)
    choice(::Type{<:Enum}; kw...)
    choice(metavar::AbstractString, ::Type{<:Enum}; kw...)

Enumerated-choice value parser.

Parses one value from a fixed set of accepted strings, or from the string names of
an enum type. Matching is case-insensitive by default.

# Keywords
- `case_insensitive::Bool = true`: whether matching should ignore case
- `metavar::String`: placeholder used in usage/help output

# Examples
```jldoctest
julia> using OptParse

julia> mode = choice("MODE", ["debug", "release"]);

julia> optparse(arg(mode), ["DEBUG"])
"DEBUG"

julia> @enum LogLevel info warn error

julia> level = choice("LEVEL", LogLevel);

julia> optparse(arg(level), ["warn"])
warn::LogLevel = 1
```
"""
choice(values::AbstractVector{<:AbstractString}; kw...) = Choice(String.(values); kw...)
choice(metavar::AbstractString, values::AbstractVector{<:AbstractString}; kw...) =
    Choice(String.(values); metavar = String(metavar), kw...)
choice(::Type{AnEnum}; kw...) where {AnEnum <: Enum} = Choice(AnEnum; kw...)
choice(metavar::AbstractString, ::Type{AnEnum}; kw...) where {AnEnum <: Enum} =
    Choice(AnEnum; metavar = String(metavar), kw...)

"""
    integer(::Type{T}; kw...) where {T <: Integer}
    integer(metavar::AbstractString, ::Type{T}; kw...) where {T <: Integer}
    integer(; kw...)
    integer(metavar::AbstractString; kw...)

Integer value parser.

Parses signed or unsigned integers, optionally enforcing bounds.

# Keywords
- `min`: minimum accepted value
- `max`: maximum accepted value
- `metavar::String`: placeholder used in usage/help output

# Examples
```jldoctest
julia> using OptParse

julia> port = integer("PORT"; min = 1024, max = 65535);

julia> optparse(arg(port), ["8080"])
8080

julia> small = integer("COUNT", Int8);

julia> optparse(arg(small), ["12"])
12
```

# See Also
- [`i8`](@ref), [`i16`](@ref), [`i32`](@ref), [`i64`](@ref)
- [`u8`](@ref), [`u16`](@ref), [`u32`](@ref), [`u64`](@ref)
"""
integer(::Type{T}; kw...) where {T <: Integer} = IntegerVal{T}(; type = T, kw...)
integer(metavar::AbstractString, ::Type{T}; kw...) where {T <: Integer} =
    IntegerVal{T}(; metavar = String(metavar), type = T, kw...)
integer(; kw...) = IntegerVal{Int}(; kw...)
integer(metavar::AbstractString; kw...) = IntegerVal{Int}(; metavar = String(metavar), kw...)

"""
    i8(; kw...)
    i8(metavar::AbstractString; kw...)

Width-specific integer parser shorthands.

These constructors are aliases for [`integer`](@ref) specialized to the matching
machine integer type while preserving the same keyword arguments such as `min`,
`max`, and `metavar`.
"""
i8(; kw...) = integer(Int8; kw...)
i8(metavar::AbstractString; kw...) = integer(metavar, Int8; kw...)

"""
    i16(; kw...)
    i16(metavar::AbstractString; kw...)

Alias for [`integer`](@ref) specialized to `Int16`.
"""
i16(; kw...) = integer(Int16; kw...)
i16(metavar::AbstractString; kw...) = integer(metavar, Int16; kw...)

"""
    i32(; kw...)
    i32(metavar::AbstractString; kw...)

Alias for [`integer`](@ref) specialized to `Int32`.
"""
i32(; kw...) = integer(Int32; kw...)
i32(metavar::AbstractString; kw...) = integer(metavar, Int32; kw...)

"""
    i64(; kw...)
    i64(metavar::AbstractString; kw...)

Alias for [`integer`](@ref) specialized to `Int64`.
"""
i64(; kw...) = integer(Int64; kw...)
i64(metavar::AbstractString; kw...) = integer(metavar, Int64; kw...)

"""
    u8(; kw...)
    u8(metavar::AbstractString; kw...)

Alias for [`integer`](@ref) specialized to `UInt8`.
"""
u8(; kw...) = integer(UInt8; kw...)
u8(metavar::AbstractString; kw...) = integer(metavar, UInt8; kw...)

"""
    u16(; kw...)
    u16(metavar::AbstractString; kw...)

Alias for [`integer`](@ref) specialized to `UInt16`.
"""
u16(; kw...) = integer(UInt16; kw...)
u16(metavar::AbstractString; kw...) = integer(metavar, UInt16; kw...)

"""
    u32(; kw...)
    u32(metavar::AbstractString; kw...)

Alias for [`integer`](@ref) specialized to `UInt32`.
"""
u32(; kw...) = integer(UInt32; kw...)
u32(metavar::AbstractString; kw...) = integer(metavar, UInt32; kw...)

"""
    u64(; kw...)
    u64(metavar::AbstractString; kw...)

Alias for [`integer`](@ref) specialized to `UInt64`.
"""
u64(; kw...) = integer(UInt64; kw...)
u64(metavar::AbstractString; kw...) = integer(metavar, UInt64; kw...)

"""
    flt(::Type{T}; kw...) where {T}
    flt(metavar::AbstractString, ::Type{T}; kw...) where {T}
    flt(; kw...)
    flt(metavar::AbstractString; kw...)

Floating-point value parser.

Parses floating-point values, optionally enforcing bounds and controlling whether
`Inf` and `NaN` are accepted.

# Keywords
- `min`: minimum accepted value
- `max`: maximum accepted value
- `allow_infinity::Bool = false`
- `allow_nan::Bool = false`
- `metavar::String`: placeholder used in usage/help output

# Examples
```jldoctest
julia> using OptParse

julia> ratio = flt("RATIO"; min = 0.0, max = 1.0);

julia> optparse(arg(ratio), ["0.25"])
0.25

julia> x = flt("X", Float32);

julia> typeof(optparse(arg(x), ["1.5"]))
Float32
```

# See Also
- [`flt32`](@ref)
- [`flt64`](@ref)
"""
flt(::Type{T}; kw...) where {T} = FloatVal{T}(; type = T, kw...)
flt(metavar::AbstractString, ::Type{T}; kw...) where {T} =
    FloatVal{T}(; metavar = String(metavar), type = T, kw...)
flt(; kw...) = flt64(; kw...)
flt(metavar::AbstractString; kw...) = flt64(metavar; kw...)

"""
    flt32(; kw...)
    flt32(metavar::AbstractString; kw...)

Typed floating-point parser shorthands.

These are aliases for [`flt`](@ref) specialized to `Float32` and `Float64`.
"""
flt32(; kw...) = flt(Float32; kw...)
flt32(metavar::AbstractString; kw...) = flt(metavar, Float32; kw...)

"""
    flt64(; kw...)
    flt64(metavar::AbstractString; kw...)

Alias for [`flt`](@ref) specialized to `Float64`.
"""
flt64(; kw...) = flt(Float64; kw...)
flt64(metavar::AbstractString; kw...) = flt(metavar, Float64; kw...)

"""
    uuid(; kw...)
    uuid(metavar::AbstractString; kw...)

UUID value parser.

Parses UUID strings into `UUID` values and can restrict accepted UUID versions.

# Keywords
- `allowed_versions::Vector{Int} = Int[]`: accepted UUID versions. An empty vector
  accepts any valid UUID version.
- `metavar::String`: placeholder used in usage/help output

# Examples
```jldoctest
julia> using OptParse, UUIDs

julia> id = uuid("ID");

julia> val = optparse(arg(id), ["550e8400-e29b-41d4-a716-446655440000"]);

julia> typeof(val)
UUID
```
"""
uuid(; kw...) = UUIDVal{UUID}(; kw...)
uuid(metavar::AbstractString; kw...) = UUIDVal{UUID}(; metavar = String(metavar), kw...)

# TODO: maybe add also file and directory
"""
    path(; kw...)
    path(metavar::AbstractString; kw...)

Filesystem path value parser.

Currently validates that the provided path exists as a file, and can additionally
require the path to be absolute.

# Keywords
- `absolute::Bool = false`: require an absolute path
- `metavar::String`: placeholder used in usage/help output

# Examples
```jldoctest
julia> using OptParse

julia> file = path("FILE");

julia> file isa OptParse.AbstractValueParser{String}
true
```
"""
path(; kw...) = PathVal{String}(; kw...)
path(metavar::AbstractString; kw...) = PathVal{String}(; metavar = String(metavar), kw...)
