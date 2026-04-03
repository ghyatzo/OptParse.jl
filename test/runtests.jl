include("helpers.jl")

@testset "Value Parsers" begin

    include("unit/valueparsers/string.jl")
    include("unit/valueparsers/choice.jl")
    include("unit/valueparsers/integer.jl")
    include("unit/valueparsers/float.jl")
    include("unit/valueparsers/uuid.jl")
    include("unit/valueparsers/path.jl")

end

@testset "Primitives" failfast=true begin

    @testset "Constant parser" begin
        include("unit/primitives/constant.jl")
    end

    @testset "Flag parser" begin
        include("unit/primitives/flag.jl")
    end

    @testset "Option parser" begin
        include("unit/primitives/option.jl")
    end

    @testset "Arg parser" begin
        include("unit/primitives/arg.jl")
    end

    @testset "Cmd parser" begin
        include("unit/primitives/cmd.jl")
    end
end

@testset "Constructors" failfast=true begin

    @testset "Combine" begin
        include("unit/constructors/combine.jl")
    end

    @testset "Objects" begin
        include("unit/constructors/object.jl")
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

@testset "Modifiers" failfast=true begin

    # @testset "Optional parser" begin
    #     include("unit/modifiers/optional.jl")
    # end

    @testset "Default Modifier" begin
        include("unit/modifiers/default.jl")
    end

    @testset "Multiple Modifier" begin
        include("unit/modifiers/multiple.jl")
    end

end

@testset "Integration Tests" failfast=true begin

    @testset "Argparse" begin
        include("integration/argparse.jl")
    end

    @testset "Argv Normalization" begin
        include("unit/core/normalize_argv.jl")
    end
end

@testset "Trimming" begin
    include("trim/trimming.jl")
end

@testset "Aqua" begin
    include("aqua.jl")
end
