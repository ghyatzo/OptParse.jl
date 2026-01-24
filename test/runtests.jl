using Test
using OptParse
using OptParse:
    Context,
    parse,
    priority,
    complete,
    tstate,
    tval,
    Parser,
    ℒ_state,
    ℒ_buffer,
    ℒ_pos,
    ℒ_optterm,
    ctx_remaining,
    widen_state

using ErrorTypes
using WrappedUnions: @unionsplit, unwrap as unwrapunion
using JET
using UUIDs

# define it here for ease of use
splitparse(p::Parser, ctx::Context) = @unionsplit parse(p, ctx)
splitcomplete(p::Parser, st) = @unionsplit complete(p, st)
val(::Val{x}) where {x} = x

@testset "Value Parsers" begin

    include("valueparsers.jl")

end

@testset "Primitives" failfast=true begin

    @testset "Constant parser" begin
        include("primitives/constant.jl")
    end

    @testset "Flag parser" begin
        include("primitives/flag.jl")
    end

    @testset "Option parser" begin
        include("primitives/option.jl")
    end

    @testset "Argument parser" begin
        include("primitives/argument.jl")
    end

    @testset "Command parser" begin
        include("primitives/command.jl")
    end
end

@testset "Constructors" failfast=true begin

    @testset "Objects" begin
        include("constructors/object.jl")
    end

    @testset "Or" begin
        include("constructors/or.jl")
    end

    @testset "Tup" begin
        include("constructors/tup.jl")
    end

end

@testset "Modifiers" failfast=true begin

    # @testset "Optional parser" begin
    #     include("modifiers/optional.jl")
    # end

    @testset "withDefault Modifier" begin
        include("modifiers/withDefault.jl")
    end

    @testset "Multiple Modifier" begin
        include("modifiers/multiple.jl")
    end

end

@testset "Integration Tests" failfast=true begin

    @testset "Argparse" begin
        include("argparse.jl")
    end
end

