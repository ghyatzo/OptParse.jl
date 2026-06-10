const ObjectState{L, P} = NamedTuple{L, P}

@enum ObjectErrCode::UInt8 begin
    OBJECT_UnexpectedToken
    OBJECT_EndOfInput
    OBJECT_MaxIter
end

struct ConstrObjectError <: AbstractParseError
    code::ObjectErrCode
    token::String
end

function render_error(io::IO, err::ConstrObjectError)
    return if err.code == OBJECT_UnexpectedToken
        print(io, "Unexpected option or argument: $(err.token)")
    elseif err.code == OBJECT_EndOfInput
        print(io, "Expected an option or argument, got end of input")
    elseif err.code == OBJECT_MaxIter
        print(io, "Internal error: record parser reached its iteration limit")
    else
        print(io, "unreachable")
    end
end

struct ConstrObject{T, E, S, P, R} <: AbstractParser{T, E, S, P, R}
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
    parsers_errors = map(terr, parsers_t)

    parsers_obj_tval = NamedTuple{labels, Tuple{parsers_tvals...}}
    init_state = NamedTuple{labels, Tuple{parsers_tstates...}}(map(p -> p.initialState, parsers))

    return ConstrObject{
        parsers_obj_tval,
        Union{ConstrObjectError, parsers_errors...},
        typeof(init_state),
        typeof(parsers_obj),
        mapreduce(p -> priority(p), max, parsers_obj),
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

@autospecialize p function helpentries(p::ConstrObject{T, _E, S, PObj}, rt::OverlayContext) where {T, _E, S <: ObjectState, PObj <: NamedTuple}
    return _object_helpentries_impl(p.parsers, rt)
end

@autospecialize p ctx function focused_helpdoc(
        p::ConstrObject{T, <:Any, S},
        ctx::Context{S},
        prefix::Vector{String},
        rt::OverlayContext
    )::HelpDoc where {T, S <: ObjectState}
    return _focused_helpdoc_object(p, ctx, prefix, rt)
end


# _object_parse_impl is provided by static/record.jl or dynamic/record.jl
# _object_complete_impl is provided by static/record.jl or dynamic/record.jl

@autospecialize p ctx function parse(p::ConstrObject{T, E, S}, ctx::Context{S}) where {T, E, S <: ObjectState}

    outctx, error, allconsumed, anysuccess = _object_parse_impl(p.parsers, ctx)

    mergedcons = merge(allconsumed)

    if anysuccess
        return InnerParseResult{S, E}(innerOk(outctx, mergedcons))
    end

    if ctx_hasnone(ctx)
        if _object_can_complete(p.parsers, ctx_state(ctx))
            return InnerParseResult{S, E}(innerOk(ctx, consumed_empty(ctx)))
        end
    end

    return InnerParseResult{S, E}(typedErr(InnerParseFailure{E}, error))
end

@autospecialize p function complete(p::ConstrObject{T, E}, st::ObjectState) where {T, E}
    return _object_complete_impl(p.parsers, st)::ParseResult{T, E}
end


# # record parser return a named tuple, that can be tagged by a @constant value ie (tag=Val(:some_action), value=10, ...)
# # we can dispatch on that tag like so:

# const Tagged{tag} = NamedTuple{N, <: Tuple{Val{tag}, Vararg}} where {N}
# f(nt::Tagged{:a}) = "this is tagged as :a"
# f(nt::Tagged{:b}) = "this is tagged as :b"
