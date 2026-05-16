using Test

# ─── Functional tests with juliac from test/Project.toml preference ───

include("runtests_inner.jl")

if OptParse.juliac
    @testset "Type Stability (juliac only)" begin
        include("unit/typestability.jl")
    end
end

# ─── Functional tests with flipped juliac via subprocess ───

@testset "OptParse (juliac=$(!OptParse.juliac))" begin
    testdir = @__DIR__
    localprefs = joinpath(testdir, "LocalPreferences.toml")
    write(localprefs, "[OptParse]\njuliac = $(!OptParse.juliac)\n")
    try
        cmd = `$(Base.julia_cmd()) --project=$testdir $(joinpath(testdir, "runtests_inner.jl"))`
        @test success(run(cmd))
    finally
        rm(localprefs; force = true)
    end
end

# ─── Mode-independent tests (run once) ───

@testset "Trimming" begin
    include("trim/trimming.jl")
end

@testset "Aqua" begin
    include("aqua.jl")
end
