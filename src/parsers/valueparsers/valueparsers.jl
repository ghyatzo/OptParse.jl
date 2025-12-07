# Value Parser interface
# struct ValueParser{T}
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
    isnothing(m) && return Err("Expected a string matching the pattern `$(s.pattern)`, but got `$input`.")
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

(c::Choice)(input::String)::Result{String, String} = let
    norminput = c.caseInsensitive ? lowercase(input) : input
    index = findfirst(==(norminput), c.values)

    isnothing(index) && return Err("Expected of of $(join(c.values, ',')), but got $input")
    return Ok(c.values[index])
end


@kwdef struct IntegerVal{T}
    metavar::String = "INTEGER"
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


@kwdef struct FloatVal{T}
    metavar::String = "FLOAT"
    #
    type::Type = T
    min::Union{T, Nothing} = nothing
    max::Union{T, Nothing} = nothing
    allowInfinity::Bool = false
    allowNan::Bool = false
end
((f::FloatVal{T})(input::String)::Result{T, String}) where {T} = let
    val = tryparse(T, input)
    if isnothing(val)
        return Err("Expected valid float, got `$input`")
    end

    if isinf(val) && !f.allowInfinity
        return Err("Infinite floats are not allowed.")
    end

    if isnan(val) && !f.allowNan
        return Err("NaNs are not allowed.")
    end

    (!isnothing(f.min) && val < f.min) && return Err("Value $input is below the minimum: $(f.min)")
    (!isnothing(f.max) && val > f.max) && return Err("Value $input is above the maximum: $(f.max)")

    return Ok(val)
end


@kwdef struct UUIDVal{T}
    metavar::String = "UUID"
    #
    allowedVersions::Vector{Int} = Int[]
end
((u::UUIDVal)(input::String)::Result{UUID, String}) = let

    maybeuuid = try
        UUID(input)
    catch
        nothing
    end
    if isnothing(maybeuuid)
        return Err("Malformed UUID string: `$input`.")
    end

    version = uuid_version(maybeuuid)
    if isempty(u.allowedVersions) || version ∈ u.allowedVersions
        return Ok(maybeuuid)
    end

    return Err("Expected UUID of version [$(join(u.allowedVersions, ','))], but got version $version")

end


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

(parse(x::ValueParser{T}, input::String)::Result{T, String}) where {T} = @unionsplit parse(x, input)
((v::ValueParser{T})(input::String)::Result{T, String}) where {T} = @unionsplit v(input)


str(; kw...) = ValueParser{String}(StringVal{String}(; kw...))
choice(values::Vector{T}; kw...) where {T} = ValueParser{T}(Choice(; values, kw...))
integer(::Type{T}; kw...) where {T} = ValueParser{T}(IntegerVal{T}(; type = T, kw...))
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
flt64(; kw...) = flt(Float64; kw...)
flt32(; kw...) = flt(Float32; kw...)
flt(; kw...) = flt64(; kw...)

uuid(; kw...) = ValueParser{UUID}(UUIDVal{UUID}(; kw...))
