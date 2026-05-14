@enum ConstructErrCode::UInt8 begin
    CONSTRUCT_MakeFailed
end

@generated function construct_type_name(::Type{T}) where {T}
    return :($(string(T)))
end

modconstruct_error(code::ConstructErrCode; token = "", detail = "", subject = "") =
    mkerror(
    CompletePhase,
    ERR_ModConstruct,
    UInt8(code);
    token,
    detail,
    trace = isempty(subject) ? ErrorSite[] : ErrorSite[ErrorSite(CompletePhase, ERR_ModConstruct, subject)]
)

function modconstruct_render_error(io::IO, code::ConstructErrCode, err::ParseError)
    return if code == CONSTRUCT_MakeFailed
        print(io, "Could not construct type ", err.token)
        !isempty(err.detail) && print(io, ". ", err.detail)
    else
        print(io, "unreachable")
    end
end


struct ModConstruct{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    parser::P

    function ModConstruct(p::AbstractParser{K, S, prio}, ::Type{T}) where {
            T, K <: Union{NamedTuple, Tuple}, S, prio,
        }

        if !Base.isstructtype(T)
            throw(ArgumentError("Type $T must be a struct type."))
        end

        @static if juliac
            if !Base.isconcretetype(T)
                throw(ArgumentError("Type $T is not a concrete type."))
            end
        end

        return new{T, S, prio, typeof(p)}(p.initialState, p)
    end
end

struct ModConstructExact{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    parser::P

    function ModConstructExact(p::AbstractParser{K, S, prio}, ::Type{T}) where {
            T, K <: Union{NamedTuple, Tuple}, S, prio,
        }

        if !Base.isstructtype(T)
            throw(ArgumentError("Type $T must be a struct type."))
        end

        if !Base.isconcretetype(T)
            throw(ArgumentError("Type $T is not a concrete type."))
        end

        if K <: NamedTuple
            _validate_exact_record(T, K)
        else
            _validate_exact_sequence(T, K)
        end

        return new{T, S, prio, typeof(p)}(p.initialState, p)
    end
end

function _validate_exact_record(::Type{T}, ::Type{K}) where {T, K <: NamedTuple}
    expected = fieldnames(T)
    actual = fieldnames(K)

    if expected != actual
        throw(
            ArgumentError(
                "construct_exact requires record fields to match $(expected), got $(actual)."
            )
        )
    end

    for i in eachindex(expected)
        actual_t = fieldtype(K, i)
        target_t = fieldtype(T, i)
        if !(actual_t <: target_t)
            throw(
                ArgumentError(
                    "construct_exact field $(expected[i]) expects $(target_t), got $(actual_t)."
                )
            )
        end
    end

    return nothing
end

function _validate_exact_sequence(::Type{T}, ::Type{K}) where {T, K <: Tuple}
    if fieldcount(T) != fieldcount(K)
        throw(
            ArgumentError(
                "construct_exact requires $(fieldcount(T)) positional values, got $(fieldcount(K))."
            )
        )
    end

    for i in 1:fieldcount(T)
        actual_t = fieldtype(K, i)
        target_t = fieldtype(T, i)
        if !(actual_t <: target_t)
            throw(
                ArgumentError(
                    "construct_exact positional field $i expects $(target_t), got $(actual_t)."
                )
            )
        end
    end

    return nothing
end

@generated function _make_exact(::Type{T}, val::NamedTuple{names}) where {T, names}
    args = [:(getproperty(val, $(QuoteNode(name)))) for name in fieldnames(T)]
    return :(T($(args...)))
end

@generated function _make_exact(::Type{T}, val::Vals) where {T, Vals <: Tuple}
    args = [:(val[$i]) for i in 1:fieldcount(Vals)]
    return :(T($(args...)))
end

@inline @autospecialize p usage(p::ModConstruct) = usage(p.parser)
@inline @autospecialize p usage(p::ModConstructExact) = usage(p.parser)

@inline @autospecialize p helpentries(p::ModConstruct, rt::OverlayContext) = helpentries(p.parser, rt)
@inline @autospecialize p helpentries(p::ModConstructExact, rt::OverlayContext) = helpentries(p.parser, rt)

@inline @autospecialize p ctx focused_helpdoc(
    p::ModConstruct{T, S, _p, P},
    ctx::Context{S},
    prefix::Vector{String},
    rt::OverlayContext
) where {T, S, _p, P <: AbstractParser{<:Any, S}} =
    focused_helpdoc(p.parser, ctx, prefix, rt)

@inline @autospecialize p ctx focused_helpdoc(
    p::ModConstructExact{T, S, _p, P},
    ctx::Context{S},
    prefix::Vector{String},
    rt::OverlayContext
) where {T, S, _p, P <: AbstractParser{<:Any, S}} =
    focused_helpdoc(p.parser, ctx, prefix, rt)

@inline @autospecialize p ctx parse(p::ModConstruct{T, S, _p, P}, ctx::Context{S}) where {T, S, _p, P <: AbstractParser{<:Any, S}} =
    parse(p.parser, ctx)

@inline @autospecialize p ctx parse(p::ModConstructExact{T, S, _p, P}, ctx::Context{S}) where {T, S, _p, P <: AbstractParser{<:Any, S}} =
    parse(p.parser, ctx)

@autospecialize p function complete(
        p::ModConstruct{T, S, _p, P},
        st::S
    )::ParseResult{T} where {T, S, _p, P <: AbstractParser{<:Any, S}}

    child_res = complete(p.parser, st)
    if is_error(child_res)
        return typedErr(
            T,
            error_with_trace(
                child_res,
                CompletePhase,
                ERR_ModConstruct,
                "construct"
            )
        )
    else
        val = unwrap(child_res)
        try
            return typedOk(T, StructUtils.make(T, val))
        catch err
            err isa InterruptException && rethrow()
            return typedErr(
                T,
                modconstruct_error(
                    CONSTRUCT_MakeFailed;
                    token = construct_type_name(T),
                    detail = "Check that field names and types match and that the target constructor accepts the provided values."
                )
            )
        end
    end
end

@autospecialize p function complete(
        p::ModConstructExact{T, S, _p, P},
        st::S
    )::ParseResult{T} where {T, S, _p, P <: AbstractParser{<:Any, S}}

    child_res = complete(p.parser, st)
    if is_error(child_res)
        return typedErr(
            T,
            error_with_trace(
                child_res,
                CompletePhase,
                ERR_ModConstruct,
                "construct_exact"
            )
        )
    else
        val = unwrap(child_res)
        try
            return typedOk(T, _make_exact(T, val))
        catch err
            err isa InterruptException && rethrow()
            return typedErr(
                T,
                modconstruct_error(
                    CONSTRUCT_MakeFailed;
                    token = construct_type_name(T),
                    detail = "Check that field names, field order, and types match the exact constructor."
                )
            )
        end
    end
end
