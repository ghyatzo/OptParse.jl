# This needs a couple of parsers still to be properly tested


@testset "should create a parser that matches a subcommand and applies inner parser" begin
    inner_obj = record(
        (
            type = @constant(:show),
            progress = switch("-p", "--progress"),
            id = arg(str()),
        )
    )
    showParser = command(
        "show",
        inner_obj,
    )

    @test priority(showParser) == 15
    @test showParser.initialState === none(Option{tstate(inner_obj)})
end

@testset "should parse a basic subcommand with arguments" begin
    showParser = command(
        "show",
        record(
            (
                type = @constant(:show),
                progress = switch("-p", "--progress"),
                id = arg(str()),
            )
        ),
    )

    val = parse_ok(showParser, ["show", "--progress", "item123"])
    @test val.type == Val(:show)
    @test val.progress == true
    @test val.id == "item123"
end

@testset "should suport aliases (repeated names)" begin
    showParser = command(
        "show", "sh",
        record(
            (
                type = @constant(:show),
                progress = switch("-p", "--progress"),
                id = arg(str()),
            )
        ),
    )

    val = parse_ok(showParser, ["sh", "--progress", "item123"])
    @test val.type == Val(:show)
    @test val.progress == true
    @test val.id == "item123"
end

@testset "should fail when wrong subcommand is provided" begin
    showParser = command(
        "show",
        record(
            (
                type = @constant(:show),
                id = arg(str()),
            )
        ),
    )

    err = @test_parse_error showParser ["edit", "item123"] OptParse.ERR_ArgCommand OptParse.COMMAND_WrongName
    @test err.detail == "show"
    @test err.token == "edit"
end

@testset "should fail when subcommand is provided but required arguments are missing" begin
    editParser = command(
        "edit",
        record(
            (
                type = @constant(:edit),
                id = arg(str()),
            )
        ),
    )

    err = parse_fail(editParser, ["edit"])
    @test err.domain == OptParse.ERR_ArgArgument
    @test OptParse.ArgumentErrCode(err.code) == OptParse.ARGUMENT_TooFew
end

@testset "should handle optional options in subcommands" begin
    editParser = command(
        "edit",
        record(
            (
                type = @constant(:edit),
                editor = optional(option(("-e", "--editor"), str())),
                id = arg(str()),
            )
        ),
    )

    # Test with optional option
    # Test with optional option
    val1 = parse_ok(editParser, ["edit", "-e", "vim", "item123"])
    @test val1.type == Val(:edit)
    @test val1.editor == "vim"
    @test val1.id == "item123"

    # Test without optional option
    val2 = parse_ok(editParser, ["edit", "item456"])
    @test val2.type == Val(:edit)
    @test val2.editor === nothing
    @test val2.id == "item456"
end

@testset "should work with or() combinator for repeated subcommands" begin
    parser = or(
        command(
            "show",
            record(
                (
                    type = @constant(:show),
                    progress = switch("-p", "--progress"),
                    id = arg(str()),
                )
            ),
        ),
        command(
            "edit",
            record(
                (
                    type = @constant(:edit),
                    editor = optional(option(("-e", "--editor"), str())),
                    id = arg(str()),
                )
            ),
        ),
    )

    # Test show command
    # Test show command
    showVal = parse_ok(parser, ["show", "--progress", "item123"])
    @test showVal.type == Val(:show)
    @test showVal.progress == true
    @test showVal.id == "item123"

    # Test edit command
    editVal = parse_ok(parser, ["edit", "-e", "vim", "item456"])
    @test editVal.type == Val(:edit)
    @test editVal.editor == "vim"
    @test editVal.id == "item456"
end

@testset "should fail gracefully when no matching subcommand is found in or() combinator" begin
    parser = or(
        command(
            "show",
            record(
                (
                    type = @constant(:show),
                    id = arg(str()),
                )
            ),
        ),
        command(
            "edit",
            record(
                (
                    type = @constant(:edit),
                    id = arg(str()),
                )
            ),
        ),
    )

    err = parse_fail(parser, ["delete", "item123"])
    @test err.domain == OptParse.ERR_ConstrOr
    @test OptParse.OrErrCode(err.code) == OptParse.OR_UnexpectedToken
end

@testset "should handle empty input" begin
    showParser = command(
        "show",
        record(
            (
                type = @constant(:show),
                id = arg(str()),
            )
        ),
    )

    err = @test_parse_error showParser String[] OptParse.ERR_ArgCommand OptParse.COMMAND_EndOfInput
    @test err.detail == "show"
end

@testset "should provide correct type inference with InferValue" begin
    # or() of commands should behave like a union at runtime; we verify both branches.
    parser = or(
        command(
            "show",
            record(
                (
                    type = @constant(:show),
                    progress = switch("-p", "--progress"),
                    id = arg(str()),
                )
            ),
        ),
        command(
            "edit",
            record(
                (
                    type = @constant(:edit),
                    editor = optional(option(("-e", "--editor"), str())),
                    id = arg(str()),
                )
            ),
        ),
    )

    showVal = parse_ok(parser, ["show", "--progress", "item123"])
    @test showVal.type == Val(:show)
    @test showVal.progress == true
    @test showVal.id == "item123"

    editVal = parse_ok(parser, ["edit", "-e", "vim", "item456"])
    @test editVal.type == Val(:edit)
    @test editVal.editor == "vim"
    @test editVal.id == "item456"
end

@testset "should handle commands with same prefix names" begin
    parser = or(
        command(
            "test",
            record(
                (
                    type = @constant(:test),
                    id = arg(str()),
                )
            ),
        ),
        command(
            "testing",
            record(
                (
                    type = @constant(:testing),
                    id = arg(str()),
                )
            ),
        ),
    )

    # Should match "test" exactly, not "testing"
    val1 = parse_ok(parser, ["test", "item123"])
    @test val1.type == Val(:test)

    # Should match "testing" exactly
    val2 = parse_ok(parser, ["testing", "item456"])
    @test val2.type == Val(:testing)
end

@testset "should handle commands that look like options" begin
    parser = command(
        "--help",
        record(
            (
                type = @constant(:help),
            )
        ),
    )

    val = parse_ok(parser, ["--help"])
    @test val.type == Val(:help)
end


@testset "should handle nested commands (command within record parser)" begin
    nestedParser = record(
        (
            globalFlag = switch("--global"),
            cmd = command(
                "run",
                record(
                    (
                        type = @constant(:run),
                        script = arg(str()),
                    )
                ),
            ),
        )
    )

    val = parse_ok(nestedParser, ["--global", "run", "build"])
    @test val.globalFlag == true

    cmd = val.cmd
    @test cmd.type == Val(:run)
    @test cmd.script == "build"
end

# @testset "should fail when command is used with tuple parser and insufficient elements" begin
#     tupleParser = tuple((
#         command("start", @constant(:start)),
#         arg(str()),
#     ))

#     res = optparse(tupleParser, ["start"])
#     @test is_error(res)
#     err = unwrap_error(res)
#     @test occursin("too few arguments", string(err))
# end

@testset "should handle options terminator with commands" begin
    parser = command(
        "exec",
        record((
            type = @constant(:exec),
            args = many(arg(str())),
        )),
    )

    # Test with -- to terminate options parsing
    val = parse_ok(parser, ["exec", "--", "--not-an-option", "arg1"])
    @test val.type == Val(:exec)
    @test val.args == ["--not-an-option", "arg1"]
end

@testset "should keep treating input after -- as positional once a command is selected" begin
    parser = command(
        "test",
        record((
            type = @constant(:test),
            args = many(arg(str())),
        )),
    )

    val = parse_ok(parser, ["test", "--", "-v", "hello"])
    @test val.type == Val(:test)
    @test val.args == ["-v", "hello"]
end

@testset "should handle commands with numeric names" begin
    parser = or(
        command("v1", @constant(:version1)),
        command("v2", @constant(:version2)),
    )

    val1 = parse_ok(parser, ["v1"])
    @test val1 == Val(:version1)

    val2 = parse_ok(parser, ["v2"])
    @test val2 == Val(:version2)
end

@testset "should handle empty command name gracefully" begin
    parser = command("", @constant(:empty))

    val = parse_ok(parser, [""])
    @test val == Val(:empty)
end
