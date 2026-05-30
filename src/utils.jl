using ExprTools: splitdef, combinedef

# --- @autospecialize helpers (used at macro expansion time) ---

# Extract the name from a where-parameter (handles both :T and :(T <: Bound))
function _where_param_name(wp)
    wp isa Symbol && return wp
    if wp isa Expr && wp.head === :(<:)
        return wp.args[1]::Symbol
    end
    return nothing
end

# Split a function argument expr into (name, type_expr)
function _split_arg(arg)
    if arg isa Expr && arg.head === :(::)
        if length(arg.args) == 2
            return arg.args[1], arg.args[2]   # name::Type
        else
            return nothing, arg.args[1]        # ::Type (anonymous)
        end
    elseif arg isa Symbol
        return arg, nothing                    # bare name
    end
    return nothing, nothing
end

# Recursively strip symbols in `owned` from a type expression's curly params.
# SomeType{T, S} with owned={T} → SomeType{S}
# SomeType{T}    with owned={T} → SomeType
# Nested: Wrapper{S}  with owned={S} → nothing (fully emptied → removed from parent)
# Subtype: Foo{<:Bar{T}} with owned={T} → Foo (Bar{T} collapses → <:Bar collapses → Foo empty)
function _strip_type_params(ex, owned::Set{Symbol})
    ex isa Symbol && return (ex in owned ? nothing : ex)
    if ex isa Expr && ex.head === :curly
        stripped = []
        for p in ex.args[2:end]
            s = _strip_type_params(p, owned)
            s !== nothing && push!(stripped, s)
        end
        isempty(stripped) && return nothing
        return Expr(:curly, ex.args[1], stripped...)
    end
    if ex isa Expr && ex.head === :(<:) && length(ex.args) == 1
        inner = _strip_type_params(ex.args[1], owned)
        return inner === nothing ? nothing : Expr(:(<:), inner)
    end
    return ex
end

# Recursively collect all symbols referenced in a type expression.
# Foo{T, S} → Set([:T, :S]),  Vector{ParseResult{T}} → Set([:T])
# Also handles <:Bound (e.g., <:OrState{U} → Set([:U]))
function _collect_type_symbols(ex, out::Set{Symbol} = Set{Symbol}())
    if ex isa Symbol
        push!(out, ex)
    elseif ex isa Expr && ex.head === :curly
        for p in ex.args[2:end]
            _collect_type_symbols(p, out)
        end
    elseif ex isa Expr && ex.head === :(<:) && length(ex.args) == 1
        _collect_type_symbols(ex.args[1], out)
    end
    return out
end

# Recursively extract where-params from curly params, descending into nested types.
# Also handles <:Bound — unwraps and descends into the bound.
function _extract_nested_params!(owned, target_curly_params, preamble, param, access_expr, wp_names)
    return if param isa Symbol && haskey(wp_names, param) && param ∉ owned
        push!(owned, param)
        push!(target_curly_params, param)
        push!(preamble, :($param = $access_expr))
    elseif param isa Expr && param.head === :curly
        for (j, subparam) in enumerate(param.args[2:end])
            sub_access = :($access_expr.parameters[$j])
            _extract_nested_params!(owned, target_curly_params, preamble, subparam, sub_access, wp_names)
        end
    elseif param isa Expr && param.head === :(<:) && length(param.args) == 1
        _extract_nested_params!(owned, target_curly_params, preamble, param.args[1], access_expr, wp_names)
    end
end

"""
    @autospecialize [targets...] function_def

Conditionally despecialize function arguments for the dynamic (interactive) path.

In `juliac` mode (static/trim), the function is emitted as-is with full type parameters.
In dynamic mode, targeted arguments get `@nospecialize`, their type parameters that
appear in the `where` clause are stripped and extracted at runtime via
`typeof(arg).parameters[i]`, and the return type annotation is cleaned up.

# Examples
```julia
@autospecialize pp function tryoptparse(
        pp::AbstractParser{T, S}, args::Vector{String}
    )::ParseResult{T} where {T, S}
    ...
end
```
becomes (in dynamic mode):
```julia
function tryoptparse(
        @nospecialize(pp::AbstractParser), args::Vector{String}
    )
    T = typeof(pp).parameters[1]
    S = typeof(pp).parameters[2]
    ...
end
```

Multiple targets and partial despecialization are supported:
```julia
@autospecialize a function f(a::SomeType{A}, b::OtherType{B}) where {A, B}
    ...
end
```
→ Only `A` is extracted; `B` and its `where` constraint remain.
"""
macro autospecialize(args...)
    length(args) < 1 && error("@autospecialize requires at least a function definition")
    func_expr = last(args)
    targets = Set{Symbol}(args[i] for i in 1:(length(args) - 1))

    # Static path: emit the function definition unchanged
    juliac && return esc(func_expr)

    # No targets specified: pass through unchanged
    isempty(targets) && return esc(func_expr)

    d = splitdef(func_expr)

    where_params = get(d, :whereparams, Any[])
    # Build a name → full-expr mapping for where params
    wp_names = Dict{Symbol, Any}(_where_param_name(wp) => wp for wp in where_params if _where_param_name(wp) !== nothing)

    owned = Set{Symbol}()       # where-param names we will extract at runtime
    preamble = Expr[]           # runtime extraction statements

    # First pass: collect params referenced by non-target args.
    nontarget_params = Set{Symbol}()
    for arg in d[:args]
        arg_name, arg_type = _split_arg(arg)
        if arg_name === nothing || arg_name ∉ targets
            arg_type !== nothing && _collect_type_symbols(arg_type, nontarget_params)
        end
    end

    # Second pass: process target args — own all their where-params (including nested).
    target_curly_params = Set{Symbol}()
    for arg in d[:args]
        arg_name, arg_type = _split_arg(arg)
        if arg_name !== nothing && arg_name in targets && arg_type isa Expr && arg_type.head === :curly
            curly_params = arg_type.args[2:end]
            for (i, param) in enumerate(curly_params)
                access = :(typeof($arg_name).parameters[$i])
                _extract_nested_params!(owned, target_curly_params, preamble, param, access, wp_names)
            end
        end
    end

    # Warn about shared params (appear in both target and non-target args)
    shared = intersect(target_curly_params, nontarget_params)
    fname = get(d, :name, :unknown)
    if !isempty(shared)
        @debug "@autospecialize: in `$fname`, type parameter(s) $(join(shared, ", ")) " *
            "appear in both targeted and non-targeted arguments. " *
            "Non-targeted argument type annotations will be weakened."
    end

    # Third pass: rebuild args — @nospecialize targets, strip owned from ALL annotations.
    new_args = Any[]
    for arg in d[:args]
        arg_name, arg_type = _split_arg(arg)

        if arg_name !== nothing && arg_name in targets
            stripped_type = arg_type !== nothing ? _strip_type_params(arg_type, owned) : nothing
            # If fully stripped, fall back to bare type name for dispatch
            if stripped_type === nothing && arg_type isa Expr && arg_type.head === :curly
                stripped_type = arg_type.args[1]
            end
            inner = stripped_type !== nothing ? Expr(:(::), arg_name, stripped_type) : arg_name
            new_arg = Expr(:macrocall, Symbol("@nospecialize"), nothing, inner)
            push!(new_args, new_arg)
        elseif arg_type !== nothing && !isempty(intersect(_collect_type_symbols(arg_type), owned))
            # Non-target arg references an owned param — strip it
            stripped_type = _strip_type_params(arg_type, owned)
            if stripped_type === nothing && arg_type isa Expr && arg_type.head === :curly
                stripped_type = arg_type.args[1]
            end
            if arg_name !== nothing
                push!(new_args, stripped_type !== nothing ? Expr(:(::), arg_name, stripped_type) : arg_name)
            else
                push!(new_args, stripped_type !== nothing ? Expr(:(::), stripped_type) : arg)
            end
        else
            push!(new_args, arg)
        end
    end
    d[:args] = new_args

    # Remove owned params from where clause
    remaining_where = [wp for wp in where_params if _where_param_name(wp) ∉ owned]
    if isempty(remaining_where)
        delete!(d, :whereparams)
    else
        d[:whereparams] = remaining_where
    end

    delete!(d, :rtype)

    # Prepend runtime extraction to body
    d[:body] = Expr(:block, preamble..., d[:body])

    return esc(combinedef(d))
end

__midpoint(lo::T, hi::T) where {T <: Integer} = lo + ((hi - lo) >>> 0x01)

function tupsearchsortedfirst(v::NTuple{N, T}, x::T, lo::iT, hi::iT, o::Base.Ordering)::keytype(v) where {N, iT <: Integer, T}
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

function tupsearchsortedlast(v::NTuple{N, T}, x::T, lo::iT, hi::iT, o::Base.Ordering)::keytype(v) where {N, iT <: Integer, T}
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
function tupsearchsorted(v::NTuple{N, T}, x::T, ilo::iT, ihi::iT, o::Base.Ordering)::UnitRange{keytype(v)} where {N, iT <: Integer, T}
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
            a = tupsearchsortedfirst(v, x, lo + u, m, o)
            b = tupsearchsortedlast(v, x, m, hi - u, o)
            return a:b
        end
    end
    return (lo + 1):(hi - 1)
end


for s in [:tupsearchsortedfirst, :tupsearchsortedlast, :tupsearchsorted]
    @eval begin
        $s(v::NTuple{N, T}, x::T, o::Base.Ordering) where {N, T} = $s(v, x, firstindex(v), lastindex(v), o)
        $s(
            v::NTuple{N, T}, x::T;
            lt = isless, by = identity, rev::Union{Bool, Nothing} = nothing, order::Base.Ordering = Base.Forward
        ) where {N, T} =
            $s(v, x, Base.ord(lt, by, rev, order))
    end
end

@inline function _setindex(t::Tuple, v, i::I) where {I <: Integer}
    return ntuple(length(t)) do j
        i == j ? v : @inbounds(t[j])
    end
end

function tupsortperm(v::Tup; lt = isless, by = identity, rev::Union{Bool, Nothing} = nothing, order::Base.Ordering = Base.Forward)::NTuple{fieldcount(Tup), keytype(v)} where {Tup <: Tuple}
    sortingkey = map(by, v)
    sortedkeys = sort(sortingkey; lt, rev, order, by = identity)
    perm = ntuple(i -> zero(keytype(v)), fieldcount(Tup))

    for i in Base.OneTo(fieldcount(Tup))
        comparison = ==(sortedkeys[i])
        match_i = @something findnext(comparison, sortingkey, 1)
        while match_i in perm
            match_i = @something findnext(comparison, sortingkey, match_i + 1)
        end
        perm = _setindex(perm, match_i, i)
    end

    return perm
end

Base.@assume_effects :foldable function _sortperm_by_priority(p::PTup) where {PTup <: Tuple}
    perm = tupsortperm(p, rev = true, by = priority)
    permp = ntuple(fieldcount(PTup)) do i
        @inbounds(p[perm[i]])
    end
    return perm, permp
end

sortperm_tuple(p::PTup) where {PTup <: Tuple} = _sortperm_by_priority(p)

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
