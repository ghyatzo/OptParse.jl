using JuliaC

const TRIM_PROJ = abspath(joinpath(@__DIR__, "trimmability"))
const TRIM_VARIANTS_DIR = joinpath(TRIM_PROJ, "src", "variants")
const TRIM_CASES = (
    (name = "project_default", file = TRIM_PROJ, project = nothing),
    (name = "or_commands", file = joinpath(TRIM_VARIANTS_DIR, "or_commands.jl"), project = TRIM_PROJ),
    (name = "tuple_defaults", file = joinpath(TRIM_VARIANTS_DIR, "tuple_defaults.jl"), project = TRIM_PROJ),
    (name = "record_repeated", file = joinpath(TRIM_VARIANTS_DIR, "record_repeated.jl"), project = TRIM_PROJ),
    (name = "nested_constructors", file = joinpath(TRIM_VARIANTS_DIR, "nested_constructors.jl"), project = TRIM_PROJ),
    (name = "git like", file = joinpath(TRIM_VARIANTS_DIR, "gitlike.jl"), project = TRIM_PROJ),
)

@testset "Trimming" begin
    for case in TRIM_CASES
        @testset "$(case.name)" begin
            outdir = mktempdir()
            exeout = joinpath(outdir, case.name)

            img = isnothing(case.project) ?
                JuliaC.ImageRecipe(
                    file = case.file,
                    output_type = "--output-exe",
                    trim_mode = "safe",
                    verbose = true,
                ) :
                JuliaC.ImageRecipe(
                    file = case.file,
                    project = case.project,
                    output_type = "--output-exe",
                    trim_mode = "safe",
                    verbose = true,
                )

            JuliaC.compile_products(img)
            link = JuliaC.LinkRecipe(image_recipe = img, outname = exeout)
            JuliaC.link_products(link)
            bun = JuliaC.BundleRecipe(link_recipe = link, output_dir = outdir)
            JuliaC.bundle_products(bun)

            actual_exe = Sys.iswindows() ?
                joinpath(outdir, "bin", basename(exeout) * ".exe") :
                joinpath(outdir, "bin", basename(exeout))
            @test isfile(actual_exe)
        end
    end
end
