include("helpers.jl")

@info "Running functional tests with juliac=$(OptParse.juliac)"

@testset "Value Parsers" begin

    include("unit/valueparsers/string.jl")
    include("unit/valueparsers/choice.jl")
    include("unit/valueparsers/integer.jl")
    include("unit/valueparsers/float.jl")
    include("unit/valueparsers/uuid.jl")
    include("unit/valueparsers/path.jl")

end

@testset "Primitives" failfast = true begin

    @testset "Constant parser" begin
        include("unit/primitives/constant.jl")
    end

    @testset "Flag parser" begin
        include("unit/primitives/flag.jl")
    end

    @testset "Gate parser" begin
        include("unit/primitives/switch.jl")
    end

    @testset "Option parser" begin
        include("unit/primitives/option.jl")
    end

    @testset "Arg parser" begin
        include("unit/primitives/arg.jl")
    end

    @testset "Command parser" begin
        include("unit/primitives/command.jl")
    end

    @testset "Help command parser" begin
        include("unit/primitives/helpcommand.jl")
    end
end

@testset "Constructors" failfast = true begin

    @testset "Combine" begin
        include("unit/constructors/combine.jl")
    end

    @testset "Records" begin
        include("unit/constructors/record.jl")
    end

    @testset "Or" begin
        include("unit/constructors/or.jl")
    end

    @testset "Sequence" begin
        include("unit/constructors/sequence.jl")
    end

    @testset "Concat" begin
        include("unit/constructors/concat.jl")
    end

end

@testset "Modifiers" failfast = true begin

    # @testset "Optional parser" begin
    #     include("unit/modifiers/optional.jl")
    # end

    @testset "Default Modifier" begin
        include("unit/modifiers/default.jl")
    end

    @testset "Repeated Modifier" begin
        include("unit/modifiers/repeated.jl")
    end

    @testset "Construct Modifier" begin
        include("unit/modifiers/construct.jl")
    end

end

@testset "Integration Tests" failfast = true begin

    @testset "Optparse" begin
        include("integration/optparse.jl")
    end

end

@testset "Usage" failfast = true begin
    @testset "Tuple AST" begin
        include("unit/core/usage/usage2.jl")
    end
end

@testset "@autospecialize" begin
    include("unit/core/autospecialize.jl")
end
