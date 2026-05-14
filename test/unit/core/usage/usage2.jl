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

focus_helpdoc(parser, ctx) =
    OptParse.focused_helpdoc(
    parser,
    ctx,
    String[],
    OptParse.root_overlay_context()
)::OptParse.HelpDoc

@testset "should render simple usage leaves" begin
    @test render_usage(UsageFlag(("-v", "--verbose"))) == "--verbose"
    @test render_usage(UsageOption(("--name",), "NAME")) == "--name <NAME>"
    @test render_usage(UsageArgument("FILE")) == "<FILE>"
end

@testset "should prepend the program name when requested" begin
    usage = UsageCommand(("add",), UsageArgument("PACKAGE"))
    @test render_usage(usage; progname = "pkg") == "pkg add <PACKAGE>"
end

@testset "should collapse optional option-like entries in compact record rendering" begin
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

@testset "should collapse command alternatives into a command synopsis" begin
    usage = UsageAlternative(
        UsageCommand(("add",), UsageArgument("PKG")),
        UsageCommand(("rm",), UsageArgument("PKG")),
        UsageCommand(("up",), UsageOptional(UsageArgument("PKG"))),
    )

    @test render_usage(usage; progname = "pkg") == "pkg <COMMAND> [ARGS...]"
    @test render_usage(usage; progname = "pkg", style = :expanded) == "pkg <COMMAND> [ARGS...]"
end

@testset "should stack larger heterogeneous alternatives and elide after two lines" begin
    usage = UsageAlternative(
        UsageArgument("HOST"),
        UsageArgument("SOCKET"),
        UsageArgument("URL"),
    )

    expected = "prog <HOST>\nprog <SOCKET>\nprog ..."
    @test render_usage(usage; progname = "prog") == expected
    @test render_usage(usage; progname = "prog", style = :expanded) == expected
end

@testset "should repeat the already-rendered prefix when stacking nested alternatives" begin
    usage = UsageCommand(
        ("serve",),
        UsageObject(
            UsageOptional(UsageFlag(("-v", "--verbose"))),
            UsageAlternative(
                UsageArgument("HOST"),
                UsageArgument("SOCKET"),
                UsageArgument("URL"),
            ),
        ),
    )

    expected = "prog serve [OPTIONS] <HOST>\nprog serve [OPTIONS] <SOCKET>\nprog serve [OPTIONS] ..."
    @test render_usage(usage; progname = "prog") == expected
end

@testset "should pass the branch render style through stacked alternatives" begin
    usage = UsageAlternative(
        UsageObject(
            UsageOptional(UsageFlag(("-v", "--verbose"))),
            UsageArgument("HOST"),
        ),
        UsageObject(
            UsageOptional(UsageFlag(("-v", "--verbose"))),
            UsageArgument("SOCKET"),
        ),
        UsageObject(
            UsageOptional(UsageFlag(("-v", "--verbose"))),
            UsageArgument("URL"),
        ),
    )

    compact_expected = "prog [OPTIONS] <HOST>\nprog [OPTIONS] <SOCKET>\nprog ..."
    expanded_expected = "prog [--verbose] <HOST>\nprog [--verbose] <SOCKET>\nprog ..."

    @test render_usage(usage; progname = "prog", style = :compact) == compact_expected
    @test render_usage(usage; progname = "prog", style = :expanded) == expanded_expected
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

@testset "should stay inferred on wider heterogeneous usage records" begin
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
        UsageCommand(
            ("status",), UsageObject(
                UsageOptional(UsageFlag(("-m", "--manifest"))),
                UsageOptional(UsageFlag(("-d", "--diff"))),
            )
        ),
        UsageCommand(("pin",), UsageArgument("PKG")),
        UsageCommand(("free",), UsageArgument("PKG")),
        UsageCommand(
            ("gc",), UsageObject(
                UsageOptional(UsageFlag(("-a", "--all"))),
            )
        ),
        UsageCommand(("test",), UsageRepeat(UsageArgument("PKG"), 0, typemax(Int))),
    )

    @test_opt render_usage(usage; progname = "pkg")
    @test_opt render_usage(usage; progname = "pkg", style = Val(:expanded))
end

@testset "should build usage directly from a broad parser tree" begin
    parser = record(
        (;
            tag = @constant(:root),
            verbose = flag("-v", "--verbose"),
            experimental = switch("--experimental"),
            port = option("-p", "--port", integer("PORT")),
            input = arg(str("INPUT")),
            mode = optional(option("--mode", str("MODE"))),
            fallback = default(option("--fallback", str("FALLBACK")), "fallback"),
            extras = repeated(arg(str("EXTRA")); min = 1, max = 3),
            coordinates = sequence(
                option("--x", integer("X")),
                option("--y", integer("Y")),
            ),
            action = or(
                command(
                    "add", record(
                        (;
                            kind = @constant(:add),
                            name = arg(str("NAME")),
                        )
                    )
                ),
                command(
                    "rm", sequence(
                        arg(str("TARGET")),
                        optional(switch("--force")),
                    )
                ),
                switch("--status"),
            ),
        )
    )

    usage = OptParse.usage(parser)


    @test usage isa OptParse.UsageNode
    @test !isempty(render_usage(usage; progname = "tool"))
    if OptParse.juliac
        @test_opt OptParse.usage(parser)
    end
end

@testset "should build usage directly from combine and concat parsers" begin
    combined = combine(
        record(
            (;
                quiet = flag("-q", "--quiet"),
                host = option("--host", str("HOST")),
            )
        ),
        record(
            (;
                token = @constant(:token),
                port = option("--port", integer("PORT")),
            )
        ),
    )

    concatenated = concat(
        sequence(
            arg(str("SRC")),
            option("--from", str("FROM")),
        ),
        sequence(
            repeated(arg(str("REST")); min = 0, max = 2),
            switch("--go"),
        ),
    )

    parser = or(
        command("combined", combined),
        command("concatenated", concatenated),
    )

    @test render_usage(OptParse.usage(combined)) == "--host <HOST> --port <PORT> [OPTIONS]"
    @test render_usage(OptParse.usage(concatenated)) == "--from <FROM> --go <SRC> [<REST>] [<REST>]"
    @test render_usage(OptParse.usage(parser); progname = "tool") == "tool <COMMAND> [ARGS...]"

    if OptParse.juliac
        @test_opt OptParse.usage(combined)
        @test_opt OptParse.usage(concatenated)
        @test_opt OptParse.usage(parser)
    end
end

@testset "should hide parser usage through help information modifiers" begin
    parser = record(
        (;
            debug = flag("--debug") |> help("Debug mode", "Enable debug mode") |> hidden(),
            input = arg(str("FILE")),
        )
    )

    info = parser.parsers.debug.info

    @test info.hidden
    @test info.brief == "Debug mode"
    @test info.description == "Enable debug mode"
    @test render_usage(OptParse.usage(parser)) == "<FILE>"
    @test optparse(parser, ["--debug", "input.txt"]) == (debug = true, input = "input.txt")
    @test_opt OptParse.usage(parser)
end

@testset "should focus usage on selected nested commands" begin
    parser = record(
        (;
            verbose = flag("-v", "--verbose"),
            action = or(
                command(
                    "cmd", record(
                        (;
                            dry_run = flag("--dry-run"),
                            sub = command(
                                "subcmd", record(
                                    (;
                                        force = flag("--force"),
                                        file = arg(str("FILE")),
                                    )
                                )
                            ),
                        )
                    )
                ),
                command("other", arg(str("OTHER"))),
            ),
        )
    )

    ctx = OptParse.recover_usage_context(parser, ["-v", "cmd", "subcmd", "--unknown"])
    focused = focus_helpdoc(parser, ctx)

    @test focused.prefix == ["cmd", "subcmd"]
    @test render_usage(focused; progname = "prog") == "prog cmd subcmd [OPTIONS] <FILE>"
end

@testset "should append focused usage when rendering parse exceptions" begin
    parser = record(
        (;
            verbose = flag("-v", "--verbose"),
            action = or(
                command(
                    "cmd", record(
                        (;
                            dry_run = flag("--dry-run"),
                            sub = command(
                                "subcmd", record(
                                    (;
                                        force = flag("--force"),
                                        file = arg(str("FILE")),
                                    )
                                )
                            ),
                        )
                    )
                ),
                command("other", arg(str("OTHER"))),
            ),
        )
    )

    argv = ["-v", "cmd", "subcmd", "--unknown"]
    err = parse_fail(parser, argv)
    msg = sprint(showerror, OptParse.ParseException(parser, argv, err))

    @test occursin("Unexpected option or argument: --unknown", msg)
    @test occursin("\n\nUsage: cmd subcmd [OPTIONS] <FILE>", msg)
end

@testset "should keep local aggregate usage when focusing non-command alternatives" begin
    parser = command(
        "run", record(
            (;
                verbose = flag("-v", "--verbose"),
                target = or(
                    arg(str("HOST")),
                    option("--socket", str("SOCKET")),
                ),
            )
        )
    )

    ctx = OptParse.recover_usage_context(parser, ["run", "localhost", "--unknown"])
    focused = focus_helpdoc(parser, ctx)

    @test focused.prefix == ["run"]
    @test render_usage(focused; progname = "prog") == "prog run (--socket <SOCKET> | <HOST>) [OPTIONS]"
end

@testset "should ignore hidden usage nodes inside sequences" begin
    usage = UsageObject(
        UsageHidden(UsageArgument("IGNORED")),
        UsageArgument("FILE"),
    )

    @test render_usage(usage) == "<FILE>"
end
