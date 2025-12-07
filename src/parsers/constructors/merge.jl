#=The merge originally was a parser, but we could in theory just take a generating function and spitout a new object.=#
function __get_ith_l_t_pair(::Type{NamedTuple{l, ts}}, ::Val{i}) where {l, ts, i}
    return l[i] => fieldtype(ts, i)
end

function _merge(objs::TObjs) where {TObjs <: Tuple}
    # we just need to construct a bigass object

    child_parsers_t = map(ptypes, fieldtypes(TObjs))
    fieldcounts = map(fieldcount, child_parsers_t)
    Nfields = sum(fieldcounts)
    objsplit = (0, cumsum(fieldcounts)...)

    l_t_pairs = ntuple(Val(Nfields)) do i
        # we add a phantom 0 to allow for branchless indexing.
        # i starts from 1, and the first bigger elements is at position 2.
        # the actual object position is at position 1,
        # and the inner index is i minus all the elements of the blocks we completed already (cumsum, one position behind).
        objI = findfirst(>=(i), objsplit) - 1
        inner_I = i - objsplit[objI]

        ps_t = child_parsers_t[objI]
        __get_ith_l_t_pair(ps_t, Val(inner_I))
    end
    labels = map(first, l_t_pairs)
    types = map(last, l_t_pairs)
    parsers = ntuple(Val(Nfields)) do i
        objI = findfirst(>=(i), objsplit) - 1
        inner_I = i - objsplit[objI]

        objs[objI].parsers[inner_I]
    end

    # we even get duplicate check for "free"
    return NamedTuple{labels, Tuple{types...}}(parsers)
end
