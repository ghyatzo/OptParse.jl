# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║ Display Interface                                                          ║
# ║                                                                            ║
# ║ Extension points (implement for custom parsers):                           ║
# ║   Base.show(io::IO, p::MyParser)  — compact inline representation         ║
# ║   show_children(p::MyParser)      — children for tree display (optional)   ║
# ║   printnode(io::IO, p::MyParser)  — tree header (optional, defaults show)  ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

"""
    show_children(p::AbstractParser)
    show_children(v::AbstractValueParser)

Return the children of a parser for tree display, or `nothing` for leaf parsers.

Each child is a `Pair{String, <:AbstractParser}` where the string is a label
(field name, index, or empty for unnamed single children).

Override this to get automatic tree display in the REPL.
"""
show_children(::AbstractParser) = nothing
show_children(::AbstractValueParser) = nothing

"""
    printnode(io::IO, p)

Print the tree-header label for a parser node.
Defaults to `show(io, p)`.

Override when the tree header should be shorter than the compact form
(e.g., constructors that summarize children inline in compact mode).
"""
printnode(io::IO, p::AbstractParser) = show(io, p)
printnode(io::IO, v::AbstractValueParser) = show(io, v)


# ═══════════════════════════════════════════════════════════════════════════════
# Tree Printer
# ═══════════════════════════════════════════════════════════════════════════════

function _print_tree(io::IO, p; prefix::String = "", is_last::Bool = true, is_root::Bool = true)
    printnode(io, p)
    cs = show_children(p)
    cs === nothing && return
    n = _children_length(cs)
    for (idx, (label, child)) in enumerate(cs)
        is_child_last = idx == n
        print(io, "\n")
        connector = is_child_last ? "└─ " : "├─ "
        extension = is_child_last ? "   " : "│  "
        print(io, prefix, connector)
        if !isempty(label)
            print(io, label, ": ")
        end
        _print_tree(io, child; prefix = prefix * extension, is_last = is_child_last, is_root = false)
    end
end

_children_length(cs::AbstractVector) = length(cs)
_children_length(cs) = length(cs)


# ═══════════════════════════════════════════════════════════════════════════════
# Generic Fallbacks
# ═══════════════════════════════════════════════════════════════════════════════

function Base.show(io::IO, p::AbstractParser)
    print(io, nameof(typeof(p)), "(...)")
end

function Base.show(io::IO, v::AbstractValueParser)
    print(io, nameof(typeof(v)), "()")
end

# Tree display — interactive/REPL only.
# Not intended for trimmed binaries; the trimmer drops it when unreachable.
Base.show(io::IO, ::MIME"text/plain", p::AbstractParser) = _print_tree(io, p)
Base.show(io::IO, ::MIME"text/plain", v::AbstractValueParser) = show(io, v)


# ═══════════════════════════════════════════════════════════════════════════════
# Value Parsers
# ═══════════════════════════════════════════════════════════════════════════════

Base.show(io::IO, p::ChoiceVal) = let
    print(io, "choice(")
    print(io, join(string.(p.values), '|'))
    if !isempty(p.metavar)
        print(io, ",", p.metavar)
    end
    print(io, ")")
end
Base.show(io::IO, p::StringVal) = let
    print(io, "str(")
    if !isempty(p.metavar)
        print(io, p.metavar)
    end
    print(io, ")")
end
Base.show(io::IO, p::IntegerVal) = let
    print(io, "integer(")
    if !isnothing(p.min) || !isnothing(p.max)
        lb = isnothing(p.min) ? "" : "$(p.min)"
        ub = isnothing(p.max) ? "" : "$(p.max)"
        print(io, "$lb..$ub")
    end
    if !isempty(p.metavar)
        if !isnothing(p.min) || !isnothing(p.max)
            print(io, ",")
        end
        print(io, p.metavar)
    end
    print(io, ")")
end
Base.show(io::IO, p::FloatVal) = let
    print(io, "flt(")
    if !isnothing(p.min) || !isnothing(p.max)
        lb = isnothing(p.min) ? "" : "$(p.min)"
        ub = isnothing(p.max) ? "" : "$(p.max)"
        print(io, "$lb..$ub")
    end
    if !isempty(p.metavar)
        if !isnothing(p.min) || !isnothing(p.max)
            print(io, ",")
        end
        print(io, p.metavar)
    end
    print(io, ")")
end
Base.show(io::IO, p::UUIDVal) = let
    print(io, "uuid(")
    if !isempty(p.allowed_versions)
        print(io, join(p.allowed_versions, '|'))
    end
    if !isempty(p.metavar)
        if !isempty(p.allowed_versions)
            print(io, ",")
        end
        print(io, p.metavar)
    end
    print(io, ")")
end
Base.show(io::IO, p::PathVal) = let
    print(io, "path(")
    if !isempty(p.metavar)
        print(io, p.metavar)
    end
    print(io, ")")
end


# ═══════════════════════════════════════════════════════════════════════════════
# Primitives
# ═══════════════════════════════════════════════════════════════════════════════

Base.show(io::IO, p::ArgGate) = let
    print(io, "switch(")
    print(io, join(p.names, ", "))
    print(io, ")")
end
Base.show(io::IO, p::ArgOption) = let
    print(io, "option(")
    print(io, join(p.names, ", "))
    print(io, ", ")
    show(io, p.valparser)
    print(io, ")")
end
val(::Val{x}) where {x} = x
Base.show(io::IO, p::ArgConstant) = let
    print(io, "@constant(")
    print(io, val(p.initialState))
    print(io, ")")
end
Base.show(io::IO, p::ArgArgument) = let
    print(io, "arg(")
    if !isempty(metavar(p.valparser))
        print(io, metavar(p.valparser))
    else
        show(io, p.valparser)
    end
    print(io, ")")
end
Base.show(io::IO, p::ArgCommand) = let
    print(io, "command(")
    print(io, p.names[1])
    print(io, ")")
end

show_children(p::ArgCommand) = Pair{String, Any}["" => p.parser]


# ═══════════════════════════════════════════════════════════════════════════════
# Constructors
# ═══════════════════════════════════════════════════════════════════════════════

Base.show(io::IO, p::ConstrObject) = let
    print(io, "record(")
    print(io, join(string.(keys(p.parsers)), ", "))
    print(io, ")")
end
Base.show(io::IO, p::ConstrOr) = let
    print(io, "or(")
    print(io, length(p.parsers))
    print(io, " branches)")
end
Base.show(io::IO, p::ConstrTuple) = let
    print(io, "sequence(")
    print(io, length(p.parsers))
    print(io, " items)")
end

printnode(io::IO, ::ConstrObject) = print(io, "record")
printnode(io::IO, ::ConstrOr) = print(io, "or")
printnode(io::IO, ::ConstrTuple) = print(io, "sequence")

show_children(p::ConstrObject) = Pair{String, Any}[String(k) => v for (k, v) in pairs(p.parsers)]
show_children(p::ConstrOr) = Pair{String, Any}[string(i) => v for (i, v) in enumerate(p.parsers)]
show_children(p::ConstrTuple) = Pair{String, Any}[string(i) => v for (i, v) in enumerate(p.parsers)]


# ═══════════════════════════════════════════════════════════════════════════════
# Modifiers
# ═══════════════════════════════════════════════════════════════════════════════

function _show_optional_flag(io::IO, p::ModWithDefault)
    inner = p.parser
    if p.default === false && inner isa ArgGate
        print(io, "flag(")
        print(io, join(inner.names, ", "))
        print(io, ")")
        return true
    end
    return false
end

Base.show(io::IO, p::ModWithDefault) = let
    if _show_optional_flag(io, p)
        return
    end
    print(io, "default(")
    show(io, p.parser)
    print(io, ", ")
    show(io, p.default)
    print(io, ")")
end
Base.show(io::IO, p::ModMultiple) = let
    if p.min == 0 && p.max == typemax(Int)
        print(io, "many(")
        show(io, p.parser)
        print(io, ")")
        return
    elseif p.min == 1 && p.max == typemax(Int)
        print(io, "many1(")
        show(io, p.parser)
        print(io, ")")
        return
    end

    print(io, "repeated(")
    show(io, p.parser)
    print(io, "; min = ", p.min)
    p.max != typemax(Int) && print(io, ", max = ", p.max)
    print(io, ")")
end
Base.show(io::IO, p::ModHelp) = let
    if p.info.hidden && isempty(p.info.brief) && isempty(p.info.description) && isempty(p.info.footer)
        print(io, "hidden(")
    else
        print(io, "help(")
    end
    show(io, p.parser)
    print(io, ")")
end
Base.show(io::IO, p::ModConstruct{T}) where {T} = let
    print(io, "construct(")
    print(io, construct_type_name(T))
    print(io, ", ")
    show(io, p.parser)
    print(io, ")")
end
Base.show(io::IO, p::ModConstructExact{T}) where {T} = let
    print(io, "construct_exact(")
    print(io, construct_type_name(T))
    print(io, ", ")
    show(io, p.parser)
    print(io, ")")
end

# Construct/ConstructExact: tree display "sees through" the inner constructor
printnode(io::IO, p::ModConstruct{T}) where {T} = print(io, construct_type_name(T))
printnode(io::IO, p::ModConstructExact{T}) where {T} = print(io, construct_type_name(T))

function _construct_show_children(p)
    inner = p.parser
    if inner isa ConstrObject
        return Pair{String, Any}[String(k) => v for (k, v) in pairs(inner.parsers)]
    elseif inner isa ConstrTuple
        return Pair{String, Any}[string(i) => v for (i, v) in enumerate(inner.parsers)]
    else
        return Pair{String, Any}["" => inner]
    end
end

show_children(p::ModConstruct) = _construct_show_children(p)
show_children(p::ModConstructExact) = _construct_show_children(p)
