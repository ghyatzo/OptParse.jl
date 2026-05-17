struct ConstrTuple{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    parsers::P
    #
    label::String
end

@enum TupleErrCode::UInt8 begin
    TUPLE_NoRemainingParser
end

struct ConstrTupleError <: AbstractParseError
    code::TupleErrCode
    token::String
end

function render_error(io::IO, err::ConstrTupleError)
    return if err.code == TUPLE_NoRemainingParser
        if isempty(err.token)
            print(io, "No remaining tuple element could match the input")
        else
            print(io, "No remaining tuple element could match $(err.token)")
        end
    else
        print(io, "unreachable")
    end
end

ConstrTuple(parsers::PTup; label::String = "") where {PTup <: Tuple} = let
    if !all(pt <: AbstractParser for pt in fieldtypes(PTup))
        throw(ArgumentError("sequence only accepts a tuple of parsers."))
    end

    ConstrTuple{
        Tuple{map(tval, parsers)...},
        Tuple{map(tstate, parsers)...},
        mapreduce(priority, max, parsers, init = 0),
        PTup,
    }(map(p -> p.initialState, parsers), parsers, label)
end

@inline @autospecialize p function usage(p::ConstrTuple)
    UsageTuple(_usage_children(p.parsers))
end
# _tuple_helpentries_impl is provided by static/tuple.jl or dynamic/tuple.jl
# _focused_helpdoc_tuple is provided by static/tuple.jl or dynamic/tuple.jl

@autospecialize p function helpentries(p::ConstrTuple{T, S, _p, PTup}, rt::OverlayContext) where {T, S <: Tuple, _p, PTup <: Tuple}
    return _tuple_helpentries_impl(p.parsers, rt)
end

@autospecialize p ctx function focused_helpdoc(
        p::ConstrTuple{T, S},
        ctx::Context{S},
        prefix::Vector{String},
        rt::OverlayContext
    )::HelpDoc where {T, S <: Tuple}
    return _focused_helpdoc_tuple(p, ctx, prefix, rt)
end

# _tup_parse_impl is provided by static/tuple.jl or dynamic/tuple.jl
# _tuple_complete_impl is provided by static/tuple.jl or dynamic/tuple.jl

@autospecialize p ctx function parse(p::ConstrTuple{T, S}, ctx::Context{S})::InnerParseResult{S} where {T, S <: Tuple}
    return _tup_parse_impl(p.parsers, ctx)
end

@autospecialize p function complete(p::ConstrTuple{T, TState}, st::TState)::ParseResult{T} where {T, TState <: Tuple}
    cancomplete, _result = _tuple_complete_impl(p.parsers, st)

    if !cancomplete
        return typedErr(T, unwrap_error(_result))
    end

    return typedOk(T, _result)
end
