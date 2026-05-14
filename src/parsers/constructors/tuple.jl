struct ConstrTuple{T, S, p, P} <: AbstractParser{T, S, p, P}
    initialState::S
    parsers::P
    #
    label::String
end

@enum TupleErrCode::UInt8 begin
    TUPLE_NoRemainingParser
end

constrtuple_error(code::TupleErrCode; token = "", detail = "", subject = "") =
    mkerror(
    ParsePhase, ERR_ConstrTuple, UInt8(code);
    token,
    detail,
    trace = isempty(subject) ? ErrorSite[] : ErrorSite[ErrorSite(ParsePhase, ERR_ConstrTuple, subject)]
)

function constrtuple_render_error(io::IO, code::TupleErrCode, err::ParseError)
    return if code == TUPLE_NoRemainingParser
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

@inline usage(p::ConstrTuple) = UsageTuple(_usage_children(p.parsers))
function helpentries(p::ConstrTuple{T, S, _p, PTup}, rt::OverlayContext) where {T, S <: Tuple, _p, PTup <: Tuple}

    if @generated
        ex = quote
            entries = HelpEntry[]
        end
        for (i, type) in enumerate(fieldtypes(PTup))
            push!(
                ex.args,
                :(append!(entries, helpentries(p.parsers[$i], descend_child(rt))::Vector{HelpEntry}))
            )
        end
        push!(ex.args, :(return entries))
        return ex
    else
        entries = HelpEntry[]
        for (child, type) in zip(values(p.parsers), fieldtypes(PTup))
            append!(entries, helpentries(child::type, descend_child(rt))::Vector{HelpEntry})
        end
        return entries
    end

end

@inline function focused_helpdoc(
        p::ConstrTuple{T, S},
        ctx::Context{S},
        prefix::Vector{String},
        rt::OverlayContext
    )::HelpDoc where {T, S <: Tuple}
    return _focused_helpdoc_tuple(p, ctx, prefix, rt)
end

@generated function _focused_helpdoc_tuple(
        p::ConstrTuple{T, S, _p, PTup},
        ctx::Context{S},
        prefix::Vector{String},
        rt::OverlayContext
    ) where {T, _p, PTup <: Tuple, S <: Tuple}
    N = fieldcount(PTup)
    body = Expr(:block)

    for i in 1:N
        child_state_t = fieldtype(S, i)
        push!(
            body.args, quote
                child_state = ctx_state(ctx)[$i]::$child_state_t
                child_ctx = widen_restate($child_state_t, ctx, child_state)
                child_helpdoc = (focused_helpdoc(p.parsers[$i], child_ctx, prefix, descend_child(rt)))::HelpDoc

                if child_helpdoc.prefix != prefix
                    return child_helpdoc
                end

                append!(entries, helpentries(p.parsers[$i], descend_child(rt))::Vector{HelpEntry})
            end
        )
    end

    return quote
        entries = HelpEntry[]
        $body
        return HelpDoc(prefix, usage(p), helpinfo(rt), entries)
    end
end

# _tup_parse_impl is provided by static/tuple.jl or dynamic/tuple.jl
# _tuple_complete_impl is provided by static/tuple.jl or dynamic/tuple.jl

@autospecialize p ctx function parse(p::ConstrTuple{T, S}, ctx::Context{S})::InnerParseResult{S} where {T, S <: Tuple}
    return _tup_parse_impl(p.parsers, ctx)
end

@autospecialize p function complete(p::ConstrTuple{T, TState}, st::TState)::ParseResult{T} where {T, TState <: Tuple}
    cancomplete, _result = _tuple_complete_impl(p.parsers, st)

    if !cancomplete
        subject = isempty(p.label) ? "tuple" : p.label
        return typedErr(
            T,
            error_with_trace(
                _result,
                CompletePhase,
                ERR_ConstrTuple,
                subject
            )
        )
    end

    return typedOk(T, _result)
end
