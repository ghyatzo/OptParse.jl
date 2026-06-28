using Test
using OptParse

@enum Color red green blue

@testset "choices annotation on options" begin
    mode = option("--mode", choice(["fast", "safe"]))
    usage = OptParse.usage(mode)
    entry = OptParse.HelpEntry(usage, OptParse.HelpInfo())
    @test @inferred(OptParse._help_annotation(entry)) == "required  choices: fast, safe"
end

@testset "choices annotation on arguments" begin
    color = arg(choice(Color))
    usage = OptParse.usage(color)
    entry = OptParse.HelpEntry(usage, OptParse.HelpInfo())
    @test @inferred(OptParse._help_annotation(entry)) == "required  choices: red, green, blue"
end

@testset "choices + default annotation" begin
    p = default(option("--mode", choice(["fast", "safe"])), "safe")
    usage = OptParse.usage(p)
    entry = OptParse.HelpEntry(usage, OptParse.HelpInfo())
    @test @inferred(OptParse._help_annotation(entry)) == "default: safe  choices: fast, safe"
end

@testset "optional choices annotation" begin
    mode = optional(option("--mode", choice(["fast", "safe"])))
    usage = OptParse.usage(mode)
    entry = OptParse.HelpEntry(usage, OptParse.HelpInfo())
    @test @inferred(OptParse._help_annotation(entry)) == "choices: fast, safe"
end

@testset "choices with many (min=0)" begin
    mode = many(option("--mode", choice(["fast", "safe"])))
    usage = OptParse.usage(mode)
    entry = OptParse.HelpEntry(usage, OptParse.HelpInfo())
    @test @inferred(OptParse._help_annotation(entry)) == "choices: fast, safe"
end

@testset "choices with many1 (min=1)" begin
    mode = many1(option("--mode", choice(["fast", "safe"])))
    usage = OptParse.usage(mode)
    entry = OptParse.HelpEntry(usage, OptParse.HelpInfo())
    @test @inferred(OptParse._help_annotation(entry)) == "required  choices: fast, safe"
end

@testset "choices through help modifier" begin
    mode = help("Mode", description = "Select the operating mode")(option("--mode", choice(["fast", "safe"])))
    usage = OptParse.usage(mode)
    entry = OptParse.HelpEntry(usage, OptParse.HelpInfo())
    @test @inferred(OptParse._help_annotation(entry)) == "required  choices: fast, safe"
end

@testset "no choices on plain option" begin
    p = option("--port", integer("PORT"))
    usage = OptParse.usage(p)
    entry = OptParse.HelpEntry(usage, OptParse.HelpInfo())
    @test @inferred(OptParse._help_annotation(entry)) == "required"
end

@testset "no choices on default option" begin
    p = default(option("--port", integer("PORT")), 8080)
    usage = OptParse.usage(p)
    entry = OptParse.HelpEntry(usage, OptParse.HelpInfo())
    @test @inferred(OptParse._help_annotation(entry)) == "default: 8080"
end

@testset "choices in full help output" begin
    p = record((; mode = option("--mode", choice(["fast", "safe"]))))
    helptext = OptParse.generate_help(p, String[]; progname = "prog")
    @test occursin("choices: fast, safe", helptext)
    @test occursin("required", helptext)
end

@testset "choices + default in full help output" begin
    p = record((; mode = default(option("--mode", choice(["fast", "safe"])), "safe")))
    helptext = OptParse.generate_help(p, String[]; progname = "prog")
    @test occursin("default: safe  choices: fast, safe", helptext)
end

@testset "@test_opt usage for choice option" begin
    @test_opt OptParse.usage(option("--mode", choice(["fast", "safe"])))
end

@testset "@test_opt usage for choice argument" begin
    @test_opt OptParse.usage(arg(choice(["a", "b"])))
end
