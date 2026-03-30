using OptParse:
    UsageAlternative,
    UsageArgument,
    UsageCommand,
    UsageFlag,
    UsageHidden,
    UsageObject,
    UsageOption,
    UsageOptional,
    UsageRepeat,
    render_usage

@testset "should render simple usage leaves" begin
    @test render_usage(UsageFlag(("-v", "--verbose"))) == "--verbose"
    @test render_usage(UsageOption(("--name",), "NAME")) == "--name <NAME>"
    @test render_usage(UsageArgument("FILE")) == "<FILE>"
end

@testset "should prepend the program name when requested" begin
    usage = UsageCommand(("add",), UsageArgument("PACKAGE"))
    @test render_usage(usage; progname = "pkg") == "pkg add <PACKAGE>"
end

@testset "should collapse optional option-like entries in compact object rendering" begin
    usage = UsageObject(
        UsageOptional(UsageFlag(("-v", "--verbose"))),
        UsageOptional(UsageOption(("--color",), "WHEN")),
        UsageArgument("FILE"),
    )

    @test render_usage(usage; style = :compact) == "[OPTIONS] <FILE>"
    @test render_usage(usage; style = :expanded) == "[--verbose] [--color <WHEN>] <FILE>"
end

@testset "should keep required options explicit in compact rendering" begin
    usage = UsageObject(
        UsageOption(("--config",), "FILE"),
        UsageOptional(UsageFlag(("-v", "--verbose"))),
        UsageArgument("INPUT"),
    )

    @test render_usage(usage; style = :compact) == "--config <FILE> [OPTIONS] <INPUT>"
end

@testset "should render repetitions with synopsis-friendly shapes" begin
    required_many = UsageRepeat(UsageArgument("FILE"), 1, typemax(Int))
    optional_many = UsageRepeat(UsageArgument("FILE"), 0, typemax(Int))
    bounded = UsageRepeat(UsageArgument("FILE"), 2, 4)

    @test render_usage(required_many) == "<FILE>..."
    @test render_usage(optional_many) == "[<FILE>]..."
    @test render_usage(bounded) == "<FILE> <FILE> [<FILE>] [<FILE>]"
end

@testset "should parenthesize alternatives and preserve nested command structure" begin
    usage = UsageCommand(
        ("serve",),
        UsageObject(
            UsageOptional(UsageFlag(("-v", "--verbose"))),
            UsageAlternative(
                UsageArgument("HOST"),
                UsageArgument("SOCKET"),
            ),
        ),
    )

    @test render_usage(usage; progname = "prog") == "prog serve [OPTIONS] (<HOST> | <SOCKET>)"
end

@testset "should be type stable" begin
    usage = UsageCommand(
        ("serve",),
        UsageObject(
            UsageOptional(UsageFlag(("-v", "--verbose"))),
            UsageAlternative(
                UsageArgument("HOST"),
                UsageArgument("SOCKET"),
            ),
        ),
    )

    @test_opt render_usage(usage; progname = "prog")
end

@testset "should stay inferred on wider heterogeneous usage objects" begin
    usage = UsageCommand(
        ("serve",),
        UsageObject(
            UsageOptional(UsageFlag(("-v", "--verbose"))),
            UsageOptional(UsageOption(("--color",), "WHEN")),
            UsageOption(("--config",), "FILE"),
            UsageOptional(UsageFlag(("-q", "--quiet"))),
            UsageAlternative(
                UsageArgument("HOST"),
                UsageArgument("SOCKET"),
                UsageArgument("URL"),
                UsageArgument("TARGET"),
            ),
            UsageOptional(UsageOption(("--mode",), "MODE")),
            UsageHidden(UsageArgument("IGNORED")),
            UsageRepeat(UsageArgument("FILE"), 0, typemax(Int)),
            UsageArgument("INPUT"),
            UsageOptional(UsageFlag(("-n", "--dry-run"))),
            UsageOptional(UsageOption(("--format",), "FORMAT")),
            UsageRepeat(UsageArgument("EXTRA"), 1, 3),
        ),
    )

    @test_opt render_usage(usage; progname = "prog")
    @test_opt render_usage(usage; progname = "prog", style = Val(:expanded))
end

@testset "should stay inferred on wide command alternatives" begin
    usage = UsageAlternative(
        UsageCommand(("add",), UsageArgument("PKG")),
        UsageCommand(("rm",), UsageArgument("PKG")),
        UsageCommand(("up",), UsageOptional(UsageArgument("PKG"))),
        UsageCommand(("status",), UsageObject(
            UsageOptional(UsageFlag(("-m", "--manifest"))),
            UsageOptional(UsageFlag(("-d", "--diff"))),
        )),
        UsageCommand(("pin",), UsageArgument("PKG")),
        UsageCommand(("free",), UsageArgument("PKG")),
        UsageCommand(("gc",), UsageObject(
            UsageOptional(UsageFlag(("-a", "--all"))),
        )),
        UsageCommand(("test",), UsageRepeat(UsageArgument("PKG"), 0, typemax(Int))),
    )

    @test_opt render_usage(usage; progname = "pkg")
    @test_opt render_usage(usage; progname = "pkg", style = Val(:expanded))
end

@testset "should ignore hidden usage nodes inside sequences" begin
    usage = UsageObject(
        UsageHidden(UsageArgument("IGNORED")),
        UsageArgument("FILE"),
    )

    @test render_usage(usage) == "<FILE>"
end
