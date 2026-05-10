@testset "should parse bare help into an empty scope" begin
    req = parse_ok(helpcommand(), ["help"])

    @test req isa HelpRequest
    @test req.argv == String[]
    @test valuetype(helpcommand()) == HelpRequest
end

@testset "should parse nested help scope" begin
    req = parse_ok(helpcommand(), ["help", "remote", "add"])

    @test req.argv == ["remote", "add"]
end

@testset "should support aliases" begin
    req = parse_ok(helpcommand("help", "h"), ["h", "serve"])

    @test req.argv == ["serve"]
end

@testset "should carry command usage shape" begin
    usage = OptParse.render_usage(OptParse.usage(helpcommand()))

    @test usage == "help [<COMMAND>]..."
end
