macro unroll(N::Int, loop)
    Base.isexpr(loop, :for) || error("only works on for loops")
    Base.isexpr(loop.args[1], :(=)) || error("This loop pattern isn't supported")
    val, itr = esc.(loop.args[1].args)
    body = esc(loop.args[2])
    # @gensym loopend
    # label = :(@label $loopend)
    # goto = :(@goto $loopend)
    out = Expr(:block, :(itr = $itr), :(next = iterate(itr)))
    unrolled = map(1:N) do _
        quote
            isnothing(next) && @goto loopend
            $val, state = next
            $body
            next = iterate(itr, state)
        end
    end
    append!(out.args, unrolled)
    remainder = quote
        while !isnothing(next)
            $val, state = next
            $body
            next = iterate(itr, state)
        end
        @label loopend
    end
    push!(out.args, remainder)
    out
end

__midpoint(lo::T, hi::T) where {T <: Integer} = lo + ((hi - lo) >>> 0x01)

function tupsearchsortedfirst(v::NTuple{N, T}, x::T, lo::iT, hi::iT, o::Base.Ordering)::keytype(v) where {N,iT <: Integer, T}
    u = one(T)
    lo = lo - u
    hi = hi + u
    len = hi - lo
    while len != 0
        half_len = len >>> 0x01
        m = lo + half_len
        if Base.lt(o, @inbounds(v[m]), x)
            lo = m + one(T)
            len -= half_len + one(T)
        else
            hi = m
            len = half_len
        end
    end
    return lo
end

function tupsearchsortedlast(v::NTuple{N,T}, x::T, lo::iT, hi::iT, o::Base.Ordering)::keytype(v) where {N, iT<:Integer, T}
    u = one(T)
    lo = lo - u
    hi = hi + u
    while lo != hi - u
        m = __midpoint(lo, hi)
        if Base.lt(o, x, @inbounds(v[m]))
            hi = m
        else
            lo = m
        end
    end
    return lo
end

# returns the range of indices of v equivalent to x
# if v does not contain x, returns a 0-length range
# indicating the insertion point of x
function tupsearchsorted(v::NTuple{N, T}, x::T, ilo::iT, ihi::iT, o::Base.Ordering)::UnitRange{keytype(v)} where {N, iT<:Integer, T}
    u = T(1)
    lo = ilo - u
    hi = ihi + u
    while lo != hi - u
        m = __midpoint(lo, hi)
        if Base.lt(o, @inbounds(v[m]), x)
            lo = m
        elseif Base.lt(o, x, @inbounds(v[m]))
            hi = m
        else
            a = tupsearchsortedfirst(v, x, lo+u, m, o)
            b = tupsearchsortedlast(v, x, m, hi-u, o)
            return a : b
        end
    end
    return (lo + 1) : (hi - 1)
end


for s in [:tupsearchsortedfirst, :tupsearchsortedlast, :tupsearchsorted]
    @eval begin
        $s(v::NTuple{N,T}, x::T, o::Base.Ordering) where {N,T} = $s(v,x,firstindex(v),lastindex(v),o)
        $s(v::NTuple{N,T}, x::T;
           lt=isless, by=identity, rev::Union{Bool,Nothing}=nothing, order::Base.Ordering=Base.Forward) where {N,T} =
            $s(v,x,Base.ord(lt,by,rev,order))
    end
end

@inline function _setindex(t::Tuple, v, i::I) where {I<:Integer}
    ntuple(length(t)) do j
        i == j ? v : @inbounds(t[j])
    end
end

function tupsortperm(v::Tup; lt=isless, by=identity, rev::Union{Bool,Nothing}=nothing, order::Base.Ordering=Base.Forward)::NTuple{fieldcount(Tup), keytype(v)} where {Tup <: Tuple}
    sortingkey = map(by, v)
    sortedkeys = sort(sortingkey; lt, rev, order, by=identity)
    perm = ntuple(i -> zero(keytype(v)), fieldcount(Tup))

    for i in Base.OneTo(fieldcount(Tup))
        comparison = ==(sortedkeys[i])
        match_i = @something findnext(comparison, sortingkey, 1)
        while match_i in perm
            match_i = @something findnext(comparison, sortingkey, match_i+1)
        end
        perm = _setindex(perm, match_i, i)
    end

    perm
end

# # juliac-compatible print(::IO, ::VersionNumber) with explicitly `@inline`d `join` calls...
# function print_vnum_juliac(io::IO, v::VersionNumber)
#     v == typemax(VersionNumber) && return print(io, "∞")
#     print(io, v.major)
#     print(io, '.')
#     print(io, v.minor)
#     print(io, '.')
#     print(io, v.patch)
#     if !isempty(v.prerelease)
#         print(io, '-')
#         @inline join(io, v.prerelease, '.')
#     end
#     if !isempty(v.build)
#         print(io, '+')
#         @inline join(io, v.build, '.')
#     end
#     return
# end

# # juliac-compatible `Base.printstyled`
# function printstyled_juliac(io::IO, str::String; bold = false, color::Symbol = :normal)
#     # TODO: Base.printstyled splits on \n and prints each line separately
#     @assert !occursin('\n', str)
#     use_color = isatty(io)
#     if use_color
#         color === :red && write(io, "\e[31m")
#         color === :green && write(io, "\e[32m")
#         color === :blue && write(io, "\e[34m")
#         color === :normal && write(io, "\e[0m")
#         bold && write(io, "\e[1m")
#     end
#     print(io, str)
#     if use_color
#         bold && write(io, "\e[22m")
#         color in (:red, :green, :blue) && write(io, "\e[39m")
#     end
#     return
# end