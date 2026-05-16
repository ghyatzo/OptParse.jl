# Juliac-specific type stability tests.
# These verify @test_opt on parse/complete/optparse/usage for complex parsers,
# which is only expected to be fully type-stable in juliac (static) mode.

@testset "Record parse/complete infers" begin
    obj = record(
        "test", (
            cst = @constant(10),
            option = option("--host", str(; metavar = "HOST")),
            flag = switch("--verbose", "-v"),
            flag2 = switch("--test"),
            arg = arg(str(; metavar = "TEST")),
        )
    )
    ctx = mkctx(["--verbose", "--host", "me", "--test", "--", "--test"], obj.initialState)
    @test_opt parse((obj), ctx)

    res = splitparse(obj, ctx)
    succ = unwrap(res)
    @test_opt complete((obj), res_nextstate(succ))
end

@testset "Or optparse infers" begin
    parser = or(
        record((verbose = switch("-v"),)),
        record((version = switch("-v"),)),
        record((verify = switch("-v"),)),
    )
    @test_opt optparse(parser, ["-v"])
end

@testset "Usage on broad parser tree infers" begin
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
    @test_opt OptParse.usage(parser)
end

@testset "Usage on combine/concat/or infers" begin
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

    @test_opt OptParse.usage(combined)
    @test_opt OptParse.usage(concatenated)
    @test_opt OptParse.usage(parser)
end

@testset "Default modifier parse/optparse infers" begin
    parser = record(
        (
            port = option(("-p", "--port"), integer(; min = 1024, max = 0xffff)),
            command = option(("-c", "--command"), str()),
            debug = switch("-d", "--debug"),
        )
    )
    @test_opt parse((parser), mkctx(["-c", "start", "-p", "3000", "-d"], parser.initialState))
    @test_opt optparse(parser, ["-c", "start", "-p", "3000", "-d"])
end
