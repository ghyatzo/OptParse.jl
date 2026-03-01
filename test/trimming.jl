using JuliaC

const TRIM_PROJ = abspath(joinpath(@__DIR__, "trimmability"))

@testset "Trimming" begin
    outdir = joinpath(TRIM_PROJ, "build")
    exeout = joinpath(outdir, "out")

    img = JuliaC.ImageRecipe(
        file = TRIM_PROJ,
        output_type = "--output-exe",
        # project = TRIM_PROJ,
        trim_mode = "safe",
        verbose = true,
    )
    JuliaC.compile_products(img)
    link = JuliaC.LinkRecipe(image_recipe=img, outname=exeout)
    JuliaC.link_products(link)
    bun = JuliaC.BundleRecipe(link_recipe=link, output_dir=outdir)
    JuliaC.bundle_products(bun)

    actual_exe = Sys.iswindows() ? joinpath(outdir, "bin", basename(exeout) * ".exe") : joinpath(outdir, "bin", basename(exeout))
    @test isfile(actual_exe)

end