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

@inline usage(p::ModConstruct) = usage(p.parser)

@inline helpentries(p::ModConstruct, rt::OverlayContext) = helpentries(p.parser, rt)

@inline focused_helpdoc(
    p::ModConstruct{T, S, _p, P},
    ctx::Context{S},
    prefix::Vector{String},
    rt::OverlayContext
) where {T, S, _p, P <: AbstractParser{<:Any, S}} =
    focused_helpdoc(p.parser, ctx, prefix, rt)

@inline parse(p::ModConstruct{T, S, _p, P}, ctx::Context{S}) where {T, S, _p, P <: AbstractParser{<:Any, S}} =
    parse(p.parser, ctx)

function complete(
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
