@testset "PathVal" begin
    p = path()
    @test metavar(p) == "PATH"
    @test (@? p("nonexistent/file.txt")) == "nonexistent/file.txt"
    @test is_error(p(""))

    pmeta = path("OUT")
    @test metavar(pmeta) == "OUT"

    pabs = path(absolute = true)
    @test is_error(pabs("relative/path"))
    abs_target = abspath("some_target")
    @test (@? pabs(abs_target)) == abs_target

    @test_opt p("nonexistent/file.txt")
end

@testset "file and directory" begin
    mktempdir() do tmp
        f_path = joinpath(tmp, "hello.txt")
        write(f_path, "hi")
        missing_path = joinpath(tmp, "missing")

        fp = file()
        @test metavar(fp) == "FILE"
        @test metavar(file("INPUT")) == "INPUT"
        @test (@? fp(f_path)) == f_path
        @test is_error(fp(missing_path)) && occursin("Could not find path", string(unwrap_error(fp(missing_path))))
        @test is_error(fp(tmp)) && occursin("Expected a file", string(unwrap_error(fp(tmp))))
        @test is_error(file(absolute = true)("rel.txt")) && occursin("absolute path", string(unwrap_error(file(absolute = true)("rel.txt"))))
        @test_opt fp(f_path)

        dp = directory()
        @test metavar(dp) == "DIR"
        @test metavar(directory("WORKDIR")) == "WORKDIR"
        @test (@? dp(tmp)) == tmp
        @test is_error(dp(missing_path)) && occursin("Could not find path", string(unwrap_error(dp(missing_path))))
        @test is_error(dp(f_path)) && occursin("Expected a directory", string(unwrap_error(dp(f_path))))
        @test is_error(directory(absolute = true)("reldir")) && occursin("absolute path", string(unwrap_error(directory(absolute = true)("reldir"))))
        @test_opt dp(tmp)
    end
end
