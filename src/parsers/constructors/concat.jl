# similar to merge but for tuple parsers, same strategy! even simpler...
# basically flatten the tuple.

function _concat(objs::TTups) where {TTups <: Tuple}
    # we just need to construct a bigass object

    child_parsers_t = map(ptypes, fieldtypes(TTups))
    fieldcounts = map(fieldcount, child_parsers_t)
    Nfields = sum(fieldcounts)
    objsplit = (0, cumsum(fieldcounts)...)

    parsers = ntuple(Val(Nfields)) do i
        objI = findfirst(>=(i), objsplit) - 1
        inner_I = i - objsplit[objI]

        objs[objI].parsers[inner_I]
    end

    # we even get duplicate check for "free"
    return parsers
end
