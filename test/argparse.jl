@testset "should parse simple flag successfully" begin
    parser = flag("-v")
    result = argparse(parser, ["-v"])

    @test !is_error(result)
    @test (@? result) == true
end

@testset "should parser options with values" begin
    parser = option("-n", str())
    result = argparse(parser, ["-n", "Andorra"])

    @test !is_error(result)
    @test (@? result) == "Andorra"
end

@testset "should parse simple flag successfully" begin
    parser = flag("-v")
    result = argparse(parser, ["--help"])

    @test is_error(result)
    @test occursin("No Matched", unwrap_error(result))
end

@testset "should handle empty arguments" begin
    parser = flag("-v")
    result = argparse(parser, String[])

    @test is_error(result)
    @test occursin("Expected a flag", unwrap_error(result))
end

@testset "should process all arguments" begin
    parser = object(
        (
            verbose = flag("-v"),
            name = option("-n", str()),
        )
    )

    result = argparse(parser, ["-v", "-n", "michele"])

    @test !is_error(result)
    @test (@? result).verbose == true
    @test (@? result).name == "michele"
end

@testset "should handle option terminator" begin
    parser = object(
        (
            verbose = flag("-v"),
        )
    )
    result = argparse(parser, ["-v", "--"])
    @test !is_error(result)
    @test (@? result).verbose == true
end

@testset "should handle complex nested parser combinations" begin
    server_parser = object(
        "Server", (
            port = option("-p", "--port", integer(min = 1, max = 25500)),
            host = option("-h", "--host", str(metavar = "HOST")),
            verbose = flag("-v"),
        )
    )

    client_parser = object(
        "Client", (
            connect = option("-c", "--connect", str(metavar = "URL")),
            timeout = option("-t", "--timeout", integer(min = 10)),
            retry = withDefault(flag("-r", "--retry"), false),
        )
    )

    main_parser = or(server_parser, client_parser)

    serverresult = argparse(main_parser, ["-h", "localhost", "--port", "8080", "-v"])

    @test !is_error(serverresult)
    val = unwrap(serverresult)
    @test hasfield(typeof(val), :port)
    @test val.port == 8080
    @test val.host == "localhost"
    @test val.verbose == true

    clientresult = argparse(main_parser, ["--connect", "www.example.com", "--timeout", "5000"])

    @test !is_error(clientresult)
    val = unwrap(clientresult)
    @test hasfield(typeof(val), :connect)
    @test val.connect == "www.example.com"
    @test val.timeout == 5000
    @test val.retry == false
end

@testset "should enforce mutual exclusivity in complex scenarios" begin

    group1 = object(
        "Group 1", (;
            allow = flag("--allow"),
            value = option("-v", integer()),
        )
    )

    group2 = object(
        "Group 2", (;
            foo = flag("--foo"),
            bar = option("--bar", str()),
        )
    )

    parser = or(group1, group2)

    conflict = argparse(parser, ["--allow", "--foo"])

    @test is_error(conflict)
    @test occursin("can't be used together", unwrap_error(conflict))
end

@testset "should handle mixed option styles" begin

    parser = object(
        (;
            unixshort = flag("-u"),
            unixlong = flag("--long"),
            dosstyle = flag("--D"),
        )
    )

    result1 = argparse(parser, ["-u", "--long", "--D"])

    @test !is_error(result1)
    val = unwrap(result1)
    @test val.unixshort == true
    @test val.unixlong == true
    @test val.dosstyle == true
end

@testset "should handle bundled short flags" begin

    parser = object(
        (;
            u = flag("-u"),
            v = flag("-v"),
            e = flag("-e"),
        )
    )

    result1 = argparse(parser, ["-uev"])

    @test !is_error(result1)
    val = unwrap(result1)
    @test val.u == true
    @test val.v == true
    @test val.e == true
end

@testset "should validate value parsers constraints in complex scenarios" begin
    server_parser = object(
        "Server", (
            port = option("-p", "--port", integer(min = 1000, max = 25500)),
            host = option("-h", "--host", str(pattern = r"^[a-zA-Z][a-zA-Z0-9_]*$")),
            verbose = withDefault(true)(flag("-v")),
        )
    )


    result = argparse(
        server_parser, [
            "-p", "8080",
            "-h", "some_server10",
        ]
    )

    @test !is_error(result)
    val = unwrap(result)
    @test val.port == 8080
    @test val.host == "some_server10"

    invalid = argparse(server_parser, ["-p", "100", "-h", "abc"])
    @test is_error(invalid)

    invalid = argparse(server_parser, ["-p", "8080", "-v", "-h", "123abc"])
    @test is_error(invalid)
    @test occursin("matching the pattern", unwrap_error(invalid))
end

@testset "should handle three way mutually exclusive options" begin
    modeA = object("Mode A", (; optionA = flag("-a")))
    modeB = object("Mode B", (; optionB = flag("-b")))
    modeC = object("Mode C", (; optionC = flag("-c")))

    parser = or(modeA, modeB, modeC)

    resultA = argparse(parser, ["-a"])
    @test !is_error(resultA)
    val = unwrap(resultA)
    val.optionA == true

    resultB = argparse(parser, ["-b"])
    @test !is_error(resultB)
    val = unwrap(resultB)
    val.optionB == true

    resultC = argparse(parser, ["-c"])
    @test !is_error(resultC)
    val = unwrap(resultC)
    val.optionC == true

    resultAB = argparse(parser, ["-a", "-b"])
    @test is_error(resultAB)
    resultCB = argparse(parser, ["-c", "-b"])
    @test is_error(resultCB)
    resultCA = argparse(parser, ["-c", "-a"])
    @test is_error(resultCA)

end

@testset "should handle nested or combinations" begin
    innerOr = or(flag("-a"), flag("-b"))

    outerOr = or(innerOr, flag("-c"))

    result = argparse(outerOr, ["-a"])
    @test !is_error(result)
    result = argparse(outerOr, ["-b"])
    @test !is_error(result)
    result = argparse(outerOr, ["-c"])
    @test !is_error(result)

end

@testset "should handle edge cases with options terminator" begin
    parser = object(
        (
            verbose = withDefault(false)(flag("-v")),
        )
    )

    res1 = argparse(parser, ["-v", "--"])
    @test !is_error(res1)
    val1 = unwrap(res1)
    @test val1.verbose == true

    res2 = argparse(parser, ["--"])

    @test !is_error(res2)
    val2 = unwrap(res2)
    @test val2.verbose == false
end

@testset "should handle argument parsers in object combinations" begin
    parser = object(
        (
            verbose = flag("-v"),
            output = option("-o", str(; metavar = "FILE")),
            input = argument(str(; metavar = "INPUT")),
        )
    )

    res = argparse(parser, ["-v", "-o", "output.txt", "input.txt"])
    @test !is_error(res)
    val = unwrap(res)
    @test val.verbose == true
    @test val.output == "output.txt"
    @test val.input == "input.txt"
end

@testset "should reproduce example behavior with arguments" begin
    group1 = object(
        "Group 1", (
            type = @constant(:group1),
            allow = flag("-a", "--allow"),
            value = option("-v", "--value", integer()),
            arg = argument(str(; metavar = "ARG")),
        )
    )

    group2 = object(
        "Group 2", (
            type = @constant(:group2),
            foo = flag("-f", "--foo"),
            bar = option("-b", "--bar", str(; metavar = "VALUE")),
        )
    )

    parser = or(group1, group2)

    group1Res = argparse(parser, ["-a", "-v", "123", "myfile.txt"])
    @test !is_error(group1Res)
    group1Val = unwrap(group1Res)
    @test group1Val.type == Val{:group1}()
    @test group1Val.allow == true
    @test group1Val.value == 123
    @test group1Val.arg == "myfile.txt"

    group2Res = argparse(parser, ["-f", "-b", "hello"])
    @test !is_error(group2Res)
    group2Val = unwrap(group2Res)
    @test group2Val.type == Val{:group2}()
    @test group2Val.foo == true
    @test group2Val.bar == "hello"
end
