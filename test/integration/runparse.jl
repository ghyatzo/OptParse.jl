# runparse writes help and errors to Core.stderr, so tests capture it through a
# pipe — the only redirect target Julia supports besides DevNull.
function capture_stderr(f)
    pipe = Pipe()
    Base.link_pipe!(pipe; reader_supports_async = true, writer_supports_async = true)
    res = redirect_stderr(pipe.in) do
        f()
    end
    close(pipe.in)
    return res, read(pipe.out, String)
end

@testset "runparse help handling" begin
    p = record((verbose = switch("-v"), name = option("-n", str())))

    # The --help flag prints help and returns nothing.
    res, out = capture_stderr(() -> runparse(p, ["--help"]))
    @test res === nothing
    @test occursin("usage", lowercase(out))

    # The help subcommand behaves like the --help flag.
    res, out = capture_stderr(() -> runparse(p, ["help"]))
    @test res === nothing
    @test occursin("usage", lowercase(out))

    # Empty argv falls back to on_empty, which defaults to the help command.
    res, out = capture_stderr(() -> runparse(p, String[]))
    @test res === nothing
    @test occursin("usage", lowercase(out))

    # Custom help flags and progname are honored.
    res, out = capture_stderr(() -> runparse(p, ["-h"]; progname = "myprog", help_flags = ["-h"]))
    @test res === nothing
    @test occursin("myprog", out)
end

@testset "runparse parsing" begin
    p = record((verbose = switch("-v"), name = option("-n", str())))

    res, _ = capture_stderr(() -> runparse(p, ["-v", "-n", "x"]))
    @test res.verbose == true
    @test res.name == "x"

    # on_empty supplies replacement argv when argv is empty.
    res, _ = capture_stderr(() -> runparse(p, String[]; on_empty = ["-v", "-n", "x"]))
    @test res.verbose == true
    @test res.name == "x"

    # -- stops help-flag stripping; tokens after it are passed through verbatim.
    q = record((input = arg(str()),))
    res, _ = capture_stderr(() -> runparse(q, ["--", "--help"]))
    @test res.input == "--help"
end
