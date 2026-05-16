const ObjectState{L, P} = NamedTuple{L, P}

@enum ObjectErrCode::UInt8 begin
    OBJECT_UnexpectedToken
    OBJECT_EndOfInput
    OBJECT_MaxIter
end

constrobject_error(code::ObjectErrCode; token = "", detail = "", subject = "") =
    mkerror(
    ERR_ConstrObject, UInt8(code);
    token,
    detail,
    subject
)

function constrobject_render_error(io::IO, code::ObjectErrCode, err::ParseError)
    return if code == OBJECT_UnexpectedToken
        print(io, "Unexpected option or argument: $(err.token)")
    elseif code == OBJECT_EndOfInput
        print(io, "Expected an option or argument, got end of input")
    elseif code == OBJECT_MaxIter
        print(io, "Internal error: record parser reached its iteration limit")
    else
        print(io, "unreachable")
    end
end

struct ConstrObject{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S # NamedTuple of the states of its parsers
    #
    parsers::P
    label::String
end


function ConstrObject(parsers_obj::NT; label = "") where {NT <: NamedTuple}
    labels = fieldnames(NT)
    N = fieldcount(NT)

    parsers_t = fieldtypes(typeof(parsers_obj))

    if !all(pt <: AbstractParser for pt in parsers_t)
        throw(ArgumentError("Record only accepts named tuples of parsers"))
    end

    parsers = values(parsers_obj)
    parsers_tvals = map(tval, parsers_t)
    parsers_tstates = map(tstate, parsers_t)

    parsers_obj_tval = NamedTuple{labels, Tuple{parsers_tvals...}}
    init_state = NamedTuple{labels, Tuple{parsers_tstates...}}(map(p -> p.initialState, parsers))

    return ConstrObject{
        parsers_obj_tval,
        typeof(init_state),
        mapreduce(p -> priority(p), max, parsers_obj),
        typeof(parsers_obj),
    }(init_state, parsers_obj, label)
end
#=
    This is does the same thing but in a different way.
    The difference is that the generated function approach
    stresses the compiler more. And deals with an AST instead of an actual value

    # @generated function gen_sorted_obj(nt::NamedTuple{labels, PTup}) where {labels, PTup}
    #   parsers_t = collect(PTup.parameters)
    #   perm = sortperm(parsers_t; by=priority, rev=true)
    #   slabels = labels[perm]
    #   :(nt[$slabels])
    # end

    we're using @assume_effects :foldable in order to tell julia that
    this function is actually allowed to be constant-folded!
    (from Mason Protter, black magic)
=#
Base.@assume_effects :foldable function _sort_obj_labels(
        labels, ::Type{PTup}
    ) where {PTup <: Tuple}

    perm = tupsortperm(fieldtypes(PTup); by = priority, rev = true)
    return ntuple(fieldcount(PTup)) do i
        @inbounds(labels[perm[i]])
    end
end

@inline usage(p::ConstrObject) = UsageObject(_usage_children(values(p.parsers)))
# _object_helpentries_impl is provided by static/record.jl or dynamic/record.jl
# _focused_helpdoc_object is provided by static/record.jl or dynamic/record.jl

@autospecialize p function helpentries(p::ConstrObject{T, S, _p, PObj}, rt::OverlayContext) where {T, S <: ObjectState, _p, PObj <: NamedTuple}
    return _object_helpentries_impl(p.parsers, rt)
end

@autospecialize p ctx function focused_helpdoc(
        p::ConstrObject{T, S},
        ctx::Context{S},
        prefix::Vector{String},
        rt::OverlayContext
    )::HelpDoc where {T, S <: ObjectState}
    return _focused_helpdoc_object(p, ctx, prefix, rt)
end


# _object_parse_impl is provided by static/record.jl or dynamic/record.jl
# _object_complete_impl is provided by static/record.jl or dynamic/record.jl

@autospecialize p ctx function parse(p::ConstrObject{T, S}, ctx::Context{S})::InnerParseResult{S} where {T, S <: ObjectState}

    outctx, error, allconsumed, anysuccess = _object_parse_impl(p.parsers, ctx)

    mergedcons = merge(allconsumed)

    if anysuccess
        return innerOk(outctx, mergedcons)
    end

    if ctx_hasnone(ctx) == 0
        all_can_complete, _ = _object_complete_impl(p.parsers, ctx_state(ctx))

        if all_can_complete
            return innerOk(ctx, consumed_empty(ctx))
        end
    end

    return innerErr(ctx, error)
end

@autospecialize p function complete(p::ConstrObject{T}, st::ObjectState)::ParseResult{T} where {T}

    cancomplete, _result = _object_complete_impl(p.parsers, st)

    if !cancomplete
        subject = isempty(p.label) ? "record" : p.label
        return typedErr(
            T,
            error_with_subject(
                _result,
                subject
            )
        )
    end

    return typedOk(T, _result)
end


# # record parser return a named tuple, that can be tagged by a @constant value ie (tag=Val(:some_action), value=10, ...)
# # we can dispatch on that tag like so:

# const Tagged{tag} = NamedTuple{N, <: Tuple{Val{tag}, Vararg}} where {N}
# f(nt::Tagged{:a}) = "this is tagged as :a"
# f(nt::Tagged{:b}) = "this is tagged as :b"
