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





struct ConstrTuple{T, E, S, P, R} <: AbstractParser{T, E, S, P, R}
    initialState::S
    parsers::P
    #
    label::String

    ConstrTuple(parsers::PTup; label::String = "") where {PTup <: Tuple} = let
        if !all(pt <: AbstractParser for pt in fieldtypes(PTup))
            throw(ArgumentError("sequence only accepts a tuple of parsers."))
        end

        new{
            Tuple{map(tval, parsers)...},
            Union{ConstrTupleError, map(terr, parsers)...},
            Tuple{map(tstate, parsers)...},
            PTup,
            mapreduce(priority, max, parsers, init = 0),
        }(map(p -> p.initialState, parsers), parsers, label)
    end
end



@inline @autospecialize p function usage(p::ConstrTuple)
    UsageTuple(_usage_children(p.parsers))
end
# _tuple_helpentries_impl is provided by static/tuple.jl or dynamic/tuple.jl
# _focused_helpdoc_tuple is provided by static/tuple.jl or dynamic/tuple.jl

@autospecialize p function helpentries(p::ConstrTuple{T, _E, S, PTup}, rt::OverlayContext) where {T, _E, S <: Tuple, PTup <: Tuple}
    return _tuple_helpentries_impl(p.parsers, rt)
end

@autospecialize p ctx function focused_helpdoc(
        p::ConstrTuple{T, <:Any, S},
        ctx::Context{S},
        prefix::Vector{String},
        rt::OverlayContext
    )::HelpDoc where {T, S <: Tuple}
    return _focused_helpdoc_tuple(p, ctx, prefix, rt)
end




# _tup_parse_impl is provided by static/tuple.jl or dynamic/tuple.jl
# _tuple_complete_impl is provided by static/tuple.jl or dynamic/tuple.jl

@autospecialize p ctx function parse(p::ConstrTuple{T, E, S}, ctx::Context{S}) where {T, E, S <: Tuple}

    outctx, error, allconsumed, found_match = _tup_parse_impl(p.parsers, ctx)
    if found_match
        return InnerParseResult{S, E}(innerOk(outctx, allconsumed))
    else
        return InnerParseResult{S, E}(typedErr(InnerParseFailure{E}, error))
    end
end

@autospecialize p function complete(p::ConstrTuple{T, E, TState}, st::TState) where {T, E, TState <: Tuple}
    return _tuple_complete_impl(p.parsers, st)::ParseResult{T, E}
end
