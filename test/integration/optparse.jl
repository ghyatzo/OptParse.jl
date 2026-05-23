@testset "should parse simple flag successfully" begin
    parser = switch("-v")
    @test parse_ok(parser, ["-v"]) == true
end

@testset "should parser options with values" begin
    parser = option("-n", str())
    @test parse_ok(parser, ["-n", "Andorra"]) == "Andorra"
end

@testset "should parse simple flag successfully" begin
    parser = switch("-v")
    err = parse_fail(parser, ["--help"])
    @test err isa OptParse.ArgGateError
    @test err.code == OptParse.GATE_NoMatch
end

@testset "should handle empty arguments" begin
    parser = switch("-v")
    err = parse_fail(parser, String[])
    @test err isa OptParse.ArgGateError
    @test err.code == OptParse.GATE_EndOfInput
end

@testset "should process all arguments" begin
    parser = record(
        (
            verbose = switch("-v"),
            name = option("-n", str()),
        )
    )

    result = parse_ok(parser, ["-v", "-n", "michele"])
    @test result.verbose == true
    @test result.name == "michele"
end

@testset "should handle option terminator" begin
    parser = record(
        (
            verbose = switch("-v"),
        )
    )
    result = parse_ok(parser, ["-v", "--"])
    @test result.verbose == true
end

@testset "should handle complex nested parser combinations" begin
    server_parser = record(
        "Server", (
            port = option("-p", "--port", integer(min = 1, max = 25500)),
            host = option("-h", "--host", str(metavar = "HOST")),
            verbose = switch("-v"),
        )
    )

    client_parser = record(
        "Client", (
            connect = option("-c", "--connect", str(metavar = "URL")),
            timeout = option("-t", "--timeout", integer(min = 10)),
            retry = default(switch("-r", "--retry"), false),
        )
    )

    main_parser = or(server_parser, client_parser)

    val = parse_ok(main_parser, ["-h", "localhost", "--port", "8080", "-v"])
    @test hasfield(typeof(val), :port)
    @test val.port == 8080
    @test val.host == "localhost"
    @test val.verbose == true

    val = parse_ok(main_parser, ["--connect", "www.example.com", "--timeout", "5000"])
    @test hasfield(typeof(val), :connect)
    @test val.connect == "www.example.com"
    @test val.timeout == 5000
    @test val.retry == false
end

@testset "should enforce mutual exclusivity in complex scenarios" begin

    group1 = record(
        "Group 1", (;
            allow = switch("--allow"),
            value = option("-v", integer()),
        )
    )

    group2 = record(
        "Group 2", (;
            foo = switch("--foo"),
            bar = option("--bar", str()),
        )
    )

    parser = or(group1, group2)

    err = parse_fail(parser, ["--allow", "--foo"])
    @test err isa OptParse.ConstrObjectError
    @test err.code == OptParse.OBJECT_UnexpectedToken
end

@testset "should handle mixed option styles" begin

    parser = record(
        (;
            unixshort = switch("-u"),
            unixlong = switch("--long"),
            dosstyle = switch("--D"),
        )
    )

    val = parse_ok(parser, ["-u", "--long", "--D"])
    @test val.unixshort == true
    @test val.unixlong == true
    @test val.dosstyle == true
end

@testset "should handle bundled short flags" begin

    parser = record(
        (;
            u = switch("-u"),
            v = switch("-v"),
            e = switch("-e"),
        )
    )

    val = parse_ok(parser, ["-uev"])
    @test val.u == true
    @test val.v == true
    @test val.e == true
end

@testset "should validate value parsers constraints in complex scenarios" begin
    server_parser = record(
        "Server", (
            port = option("-p", "--port", integer(min = 1000, max = 25500)),
            host = option("-h", "--host", str(pattern = r"^[a-zA-Z][a-zA-Z0-9_]*$")),
            verbose = default(true)(switch("-v")),
        )
    )


    val = parse_ok(
        server_parser, [
            "-p", "8080",
            "-h", "some_server10",
        ]
    )
    @test val.port == 8080
    @test val.host == "some_server10"

    err = parse_fail(server_parser, ["-p", "100", "-h", "abc"])
    @test err isa OptParse.IntegerValError

    err = parse_fail(server_parser, ["-p", "8080", "-v", "-h", "123abc"])
    @test err isa OptParse.StringValError
end

@testset "should handle three way mutually exclusive options" begin
    modeA = record("Mode A", (; optionA = switch("-a")))
    modeB = record("Mode B", (; optionB = switch("-b")))
    modeC = record("Mode C", (; optionC = switch("-c")))

    parser = or(modeA, modeB, modeC)

    val = parse_ok(parser, ["-a"])
    val.optionA == true

    val = parse_ok(parser, ["-b"])
    val.optionB == true

    val = parse_ok(parser, ["-c"])
    val.optionC == true

    @test parse_fail(parser, ["-a", "-b"]) isa OptParse.ConstrOrError
    @test parse_fail(parser, ["-c", "-b"]) isa OptParse.ConstrOrError
    @test parse_fail(parser, ["-c", "-a"]) isa OptParse.ConstrOrError

end

@testset "should handle nested or combinations" begin
    innerOr = or(switch("-a"), switch("-b"))

    outerOr = or(innerOr, switch("-c"))

    @test parse_ok(outerOr, ["-a"]) == true
    @test parse_ok(outerOr, ["-b"]) == true
    @test parse_ok(outerOr, ["-c"]) == true

end

@testset "should handle edge cases with options terminator" begin
    parser = record(
        (
            verbose = default(false)(switch("-v")),
        )
    )

    val1 = parse_ok(parser, ["-v", "--"])
    @test val1.verbose == true

    val2 = parse_ok(parser, ["--"])
    @test val2.verbose == false
end

@testset "should handle argument parsers in record combinations" begin
    parser = record(
        (
            verbose = switch("-v"),
            output = option("-o", str(; metavar = "FILE")),
            input = arg(str(; metavar = "INPUT")),
        )
    )

    val = parse_ok(parser, ["-v", "-o", "output.txt", "input.txt"])
    @test val.verbose == true
    @test val.output == "output.txt"
    @test val.input == "input.txt"
end

@testset "should reproduce example behavior with arguments" begin
    group1 = record(
        "Group 1", (
            type = @constant(:group1),
            allow = switch("-a", "--allow"),
            value = option("-v", "--value", integer()),
            arg = arg(str(; metavar = "ARG")),
        )
    )

    group2 = record(
        "Group 2", (
            type = @constant(:group2),
            foo = switch("-f", "--foo"),
            bar = option("-b", "--bar", str(; metavar = "VALUE")),
        )
    )

    parser = or(group1, group2)

    group1Val = parse_ok(parser, ["-a", "-v", "123", "myfile.txt"])
    @test group1Val.type == Val{:group1}()
    @test group1Val.allow == true
    @test group1Val.value == 123
    @test group1Val.arg == "myfile.txt"

    group2Val = parse_ok(parser, ["-f", "-b", "hello"])
    @test group2Val.type == Val{:group2}()
    @test group2Val.foo == true
    @test group2Val.bar == "hello"
end
