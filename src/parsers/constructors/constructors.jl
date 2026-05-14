include("record.jl")
include("or.jl")
include("tuple.jl")

# Conditional include: static (juliac/trim) uses @generated functions,
# dynamic (interactive) uses runtime loops with @nospecialize.
@static if juliac
    include("static/record.jl")
    include("static/or.jl")
    include("static/tuple.jl")

    @generated function _usage_children(parsers::PTup) where {PTup <: Tuple}
        N = fieldcount(PTup)

        perm = tupsortperm(fieldtypes(PTup); by = priority, rev = true)

        body = Expr(:block)
        for i in 1:N
            push!(body.args, :(children[$i] = usage(parsers[$(perm[i])])::UsageNode))
        end

        return quote
            children = Vector{UsageNode}(undef, $N)
            $body
            return children
        end
    end
else
    include("dynamic/record.jl")
    include("dynamic/or.jl")
    include("dynamic/tuple.jl")

    function _usage_children(@nospecialize(parsers::Tuple))
        N = length(parsers)

        # Extract priorities into a plain Int[] to avoid the sort closure
        # capturing and specializing on the full parser tuple type.
        prios = Int[priority(parsers[i]) for i in 1:N]
        indices = sortperm(prios; rev = true)
        children = Vector{UsageNode}(undef, N)
        for (i, j) in enumerate(indices)
            children[i] = usage(parsers[j])::UsageNode
        end
        return children
    end
end


__get_ith_l_t_pair(::Type{NamedTuple{l, ts}}, ::Val{i}) where {l, ts, i} =
    return l[i] => fieldtype(ts, i)


function _merge(objs::TObjs) where {TObjs <: Tuple}
    # we just need to construct a bigass record

    child_parsers_t = map(ptypes, fieldtypes(TObjs))
    fieldcounts = map(fieldcount, child_parsers_t)
    Nfields = sum(fieldcounts)
    objsplit = (0, cumsum(fieldcounts)...)

    l_t_pairs = ntuple(Val(Nfields)) do i
        # we add a phantom 0 to allow for branchless indexing.
        # i starts from 1, and the first bigger elements is at position 2.
        # the actual record position is at position 1,
        # and the inner index is i minus all the elements of the blocks we completed already (cumsum, one position behind).
        objI = findfirst(>=(i), objsplit) - 1
        inner_I = i - objsplit[objI]

        ps_t = child_parsers_t[objI]
        __get_ith_l_t_pair(ps_t, Val(inner_I))
    end
    labels = map(first, l_t_pairs)
    types = map(last, l_t_pairs)
    parsers = ntuple(Nfields) do i
        objI = findfirst(>=(i), objsplit) - 1
        inner_I = i - objsplit[objI]

        objs[objI].parsers[inner_I]
    end

    # we even get duplicate check for "free"
    return NamedTuple{labels, Tuple{types...}}(parsers)
end


# similar to merge but for tuple parsers, same strategy! even simpler...
# basically flatten the tuple.

function _concat(objs::TTups) where {TTups <: Tuple}
    # we just need to construct a bigass record

    child_parsers_t = map(ptypes, fieldtypes(TTups))
    fieldcounts = map(fieldcount, child_parsers_t)
    Nfields = sum(fieldcounts)
    objsplit = (0, cumsum(fieldcounts)...)

    parsers = ntuple(Val(Nfields)) do i
        objI = findfirst(>=(i), objsplit) - 1
        inner_I = i - objsplit[objI]

        objs[objI].parsers[inner_I]
    end

    return parsers
end
