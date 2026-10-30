# Base's Pair/Tuple display reaches unresolved typeinfo constructors and color callbacks under trimming.
# Render these containers directly; scalar components still use their own show methods.
_trim_string(x) = string(x)
_trim_string(x::Union{Pair, Tuple}) = sprint(_trim_show, x)

_trim_show(io::IO, x) = show(io, x)

# shortcut: widened pairs use arrow notation; add typed notation if round-trip display is required.
function _trim_show(io::IO, p::Pair)
    for (i, value) in enumerate((p.first, p.second))
        i == 2 && print(io, " => ")
        value isa Pair && print(io, '(')
        _trim_show(io, value)
        value isa Pair && print(io, ')')
    end
end

function _trim_show(io::IO, values::Tuple)
    print(io, '(')
    for (i, value) in enumerate(values)
        i > 1 && print(io, ", ")
        _trim_show(io, value)
    end
    length(values) == 1 && print(io, ',')
    print(io, ')')
end
