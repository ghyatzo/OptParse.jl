"""
    SumResults

Errors-as-values result container backed by a SumTypes.jl sum type.

API-compatible with ErrorTypes.jl: `Result{T,E}` / `Option{T}`, the `Ok` / `Err`
constructors, `is_error` / `unwrap` / `unwrap_error` / `base`, `some` / `none` and
the `@?` early-return macro.

Construction is lazy in one type parameter: `Ok(x)` holds `x` and leaves the
error parameter unset (`Result{typeof(x), Union{}}`); `Err(e)` is its mirror
image. Any typed boundary — a return annotation, an explicit `Result{T,E}(...)`
wrap, or a typed container assignment — completes the unset parameter and
widens the set one to the declared type:

    function reciprocal(x::Int)::Result{Float64, String}
        iszero(x) && return Err("Division by zero")
        Ok(1 / x)
    end
"""
module SumResults

using SumTypes

export Result, Option, Ok, Err, some, none,
    base, is_error, is_ok_and, or_else, unwrap, unwrap_error, @?

# Payload slots use `Union{T, Nothing}` rather than `T`: `Tuple{T}` is illegal
# for `T === Union{}` ("Tuple field type cannot be Union{}"), but
# `Result{T, Union{}}` is a real type here (parsers that cannot fail, e.g.
# `@constant`). The typed accessors narrow the payloads back to `T` / `E`.
"""
    Result{T, E}

Errors-as-values result: `Ok(value::T)` for success, `Err(error::E)` for
failure. Construct with `Ok(x)` / `Err(e)`; typed boundaries complete the
unset type parameter (see the `SumResults` module docs).
"""
@sum_type Result{T,E} begin
    Ok{T}(::T)
    Err{E}(::E)
end

"""
    Option{T}

Alias for `Result{T, Nothing}`, for results whose error carries no data.
Construct instances with `some(x)` and `none(T)`.
"""
const Option{T} = Result{T, Nothing}

# ---- completion at typed boundaries ----
# `Result` parameters are invariant, so widening between instantiations goes
# through this constructor. The `Union{}` parameters of `Ok` / `Err` make the
# same method the lazy-completion path. Note: when `E1 === Any` this overlaps
# SumTypes' generated `convert(::Type{<:Result{T,E}}, ::Result{T,Uninit})`;
# OptParse only widens `E` to concrete error unions.

Result{T, E1}(x::Result{Uninit, E2}) where {T, E1, E2 <: E1} = Result{T, E1}'.Err(unwrap_error(x))
Result{T1, E}(x::Result{T2, Uninit}) where {T1, T2 <: T1, E} = Result{T1, E}'.Ok(unwrap(x))

# SumTypes' generated unset-state conversions overlap the identity case when a
# parameter is `Uninit`, leaving `Result{T, Uninit}(x)` ambiguous; pin the
# degenerate instantiations so completing an already-unset boundary is a no-op.
Result{T, Uninit}(x::Result{T, Uninit}) where {T} = x
Result{Uninit, E}(x::Result{Uninit, E}) where {E} = x
Base.convert(::Type{Result{T, Uninit}}, x::Result{T, Uninit}) where {T} = x
Base.convert(::Type{Result{Uninit, E}}, x::Result{Uninit, E}) where {E} = x

function Result{T1,E1}(x::Result{T2,E2}) where {T1, T2 <: T1, E1, E2 <: E1}
    return @cases x begin
        Ok(v) => Result{T1,E1}'.Ok(v)
        Err(e) => Result{T1,E1}'.Err(e)
    end
end

Base.convert(::Type{Result{T1,E1}}, x::Result{T2,E2}) where {T1, T2 <: T1, E1, E2 <: E1} =
    Result{T1,E1}(x)

# SumTypes' generated conversions complete exactly one unset parameter and
# require the rest to be unchanged, so they miss `Result{Uninit, E2}` →
# `Result{T, E1}` with `E2 <: E1`. This fallback rebuilds the variant directly
# (instead of via `Result{T,E}'.Ok`/`.Err`, which re-enters `convert`); it is
# less specific than every generated conversion, so it only runs where they
# fall through. Drop it once SumTypes covers the general case.
_ok_result(::Type{Result{T,E}}, v) where {T,E} =
    Result{T,E}(SumTypes.constructor(Result{T,E}, Val{:Ok})((v,)))
_err_result(::Type{Result{T,E}}, e) where {T,E} =
    Result{T,E}(SumTypes.constructor(Result{T,E}, Val{:Err})((e,)))

function Base.convert(::Type{<:Result{T1,E1}}, x::Result{T2,E2}) where {T1, T2, E1, E2}
    return @cases x begin
        Ok(v) => _ok_result(Result{T1,E1}, v)
        Err(e) => _err_result(Result{T1,E1}, e)
    end
end

# ---- Option constructors ----

"""
    some(x)

Wrap `x` into an `Option{typeof(x)}`.
"""
some(x) = Option{typeof(x)}(Ok(x))

"""
    none(T)

The error value of `Option{T}`.
"""
none(::Type{T}) where {T} = Option{T}(Err(nothing))

"""
    base(x::Option{T})

Convert an `Option{T}` to a `Union{Some{T}, Nothing}`: `Some(value)` for the
success variant, `nothing` for the error variant.
"""
base(x::Option{T}) where {T} = is_error(x) ? nothing : Some(unwrap(x))

# ---- accessors ----

"""
    is_error(x::Result)

Return `true` if `x` is the error variant.
"""
is_error(x::Result) = @cases x begin
    Ok => false
    Err => true
end

"""
    unwrap(x::Result)

Return the success value of `x`. Throws if `x` is the error variant.
"""
function unwrap(x::Result{T,E})::T where {T, E}
    @cases x begin
        Ok(v) => v
        Err => throw(ArgumentError("unwrap called on an Err result"))
    end
end

"""
    unwrap_error(x::Result)

Return the error value of `x`. Throws if `x` is the success variant.
"""
function unwrap_error(x::Result{T,E})::E where {T, E}
    @cases x begin
        Ok => throw(ArgumentError("unwrap_error called on an Ok result"))
        Err(e) => e
    end
end

"""
    is_ok_and(f, x::Result)

Return `true` if `x` is the success variant and `f(unwrap(x))` is `true`.
"""
function is_ok_and(f, x::Result)::Bool
    is_error(x) && return false
    return f(unwrap(x))::Bool
end

"""
    or_else(f, x::Result)

Return `unwrap(x)` if `x` is the success variant and `f(unwrap_error(x))` otherwise.
"""
function or_else(f, x::Result)
    is_error(x) && return f(unwrap_error(x))
    return unwrap(x)
end

"""
    @?(expr)

Evaluate `expr`, which must return a [`Result`](@ref). Return the unwrapped
success value, or `return` the error from the enclosing function.

The enclosing function must have a `::Result` return annotation (or another
typed boundary), which widens the propagated error to its declared error type.
"""
macro var"?"(expr)
    return quote
        local res = $(esc(expr))
        isa(res, Result) || throw(TypeError(Symbol("@?"), Result, res))
        is_error(res) ? (return Err(unwrap_error(res))) : unwrap(res)
    end
end

end # module SumResults
