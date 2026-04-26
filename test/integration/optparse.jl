@testset "should parse simple flag successfully" begin
    parser = gate("-v")
    @test parse_ok(parser, ["-v"]) == true
end

@testset "should parser options with values" begin
    parser = option("-n", str())
    @test parse_ok(parser, ["-n", "Andorra"]) == "Andorra"
end

@testset "should parse simple flag successfully" begin
    parser = gate("-v")
    err = parse_fail(parser, ["--help"])
    @test err.domain == OptParse.ERR_ArgGate
    @test OptParse.GateErrCode(err.code) == OptParse.GATE_NoMatch
end

@testset "should handle empty arguments" begin
    parser = gate("-v")
    err = parse_fail(parser, String[])
    @test err.domain == OptParse.ERR_ArgGate
    @test OptParse.GateErrCode(err.code) == OptParse.GATE_EndOfInput
end

@testset "should process all arguments" begin
    parser = object(
        (
            verbose = gate("-v"),
            name = option("-n", str()),
        )
    )

    result = parse_ok(parser, ["-v", "-n", "michele"])
    @test result.verbose == true
    @test result.name == "michele"
end

@testset "should handle option terminator" begin
    parser = object(
        (
            verbose = gate("-v"),
        )
    )
    result = parse_ok(parser, ["-v", "--"])
    @test result.verbose == true
end

@testset "should handle complex nested parser combinations" begin
    server_parser = object(
        "Server", (
            port = option("-p", "--port", integer(min = 1, max = 25500)),
            host = option("-h", "--host", str(metavar = "HOST")),
            verbose = gate("-v"),
        )
    )

    client_parser = object(
        "Client", (
            connect = option("-c", "--connect", str(metavar = "URL")),
            timeout = option("-t", "--timeout", integer(min = 10)),
            retry = default(gate("-r", "--retry"), false),
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

    group1 = object(
        "Group 1", (;
            allow = gate("--allow"),
            value = option("-v", integer()),
        )
    )

    group2 = object(
        "Group 2", (;
            foo = gate("--foo"),
            bar = option("--bar", str()),
        )
    )

    parser = or(group1, group2)

    err = parse_fail(parser, ["--allow", "--foo"])
    @test err.domain == OptParse.ERR_ConstrObject
    @test OptParse.ObjectErrCode(err.code) == OptParse.OBJECT_UnexpectedToken
end

@testset "should handle mixed option styles" begin

    parser = object(
        (;
            unixshort = gate("-u"),
            unixlong = gate("--long"),
            dosstyle = gate("--D"),
        )
    )

    val = parse_ok(parser, ["-u", "--long", "--D"])
    @test val.unixshort == true
    @test val.unixlong == true
    @test val.dosstyle == true
end

@testset "should handle bundled short flags" begin

    parser = object(
        (;
            u = gate("-u"),
            v = gate("-v"),
            e = gate("-e"),
        )
    )

    val = parse_ok(parser, ["-uev"])
    @test val.u == true
    @test val.v == true
    @test val.e == true
end

@testset "should validate value parsers constraints in complex scenarios" begin
    server_parser = object(
        "Server", (
            port = option("-p", "--port", integer(min = 1000, max = 25500)),
            host = option("-h", "--host", str(pattern = r"^[a-zA-Z][a-zA-Z0-9_]*$")),
            verbose = default(true)(gate("-v")),
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
    @test err.domain == OptParse.ERR_IntegerVal

    err = parse_fail(server_parser, ["-p", "8080", "-v", "-h", "123abc"])
    @test err.domain == OptParse.ERR_StringVal
end

@testset "should handle three way mutually exclusive options" begin
    modeA = object("Mode A", (; optionA = gate("-a")))
    modeB = object("Mode B", (; optionB = gate("-b")))
    modeC = object("Mode C", (; optionC = gate("-c")))

    parser = or(modeA, modeB, modeC)

    val = parse_ok(parser, ["-a"])
    val.optionA == true

    val = parse_ok(parser, ["-b"])
    val.optionB == true

    val = parse_ok(parser, ["-c"])
    val.optionC == true

    @test parse_fail(parser, ["-a", "-b"]).domain == OptParse.ERR_ConstrOr
    @test parse_fail(parser, ["-c", "-b"]).domain == OptParse.ERR_ConstrOr
    @test parse_fail(parser, ["-c", "-a"]).domain == OptParse.ERR_ConstrOr

end

@testset "should handle nested or combinations" begin
    innerOr = or(gate("-a"), gate("-b"))

    outerOr = or(innerOr, gate("-c"))

    @test parse_ok(outerOr, ["-a"]) == true
    @test parse_ok(outerOr, ["-b"]) == true
    @test parse_ok(outerOr, ["-c"]) == true

end

@testset "should handle edge cases with options terminator" begin
    parser = object(
        (
            verbose = default(false)(gate("-v")),
        )
    )

    val1 = parse_ok(parser, ["-v", "--"])
    @test val1.verbose == true

    val2 = parse_ok(parser, ["--"])
    @test val2.verbose == false
end

@testset "should handle argument parsers in object combinations" begin
    parser = object(
        (
            verbose = gate("-v"),
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
    group1 = object(
        "Group 1", (
            type = @constant(:group1),
            allow = gate("-a", "--allow"),
            value = option("-v", "--value", integer()),
            arg = arg(str(; metavar = "ARG")),
        )
    )

    group2 = object(
        "Group 2", (
            type = @constant(:group2),
            foo = gate("-f", "--foo"),
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
