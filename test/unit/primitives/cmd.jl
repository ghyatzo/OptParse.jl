# This needs a couple of parsers still to be properly tested


@testset "should create a parser that matches a subcommand and applies inner parser" begin
    inner_obj = object(
        (
            type = @constant(:show),
            progress = gate("-p", "--progress"),
            id = arg(str()),
        )
    )
    showParser = cmd(
        "show",
        inner_obj,
    )

    @test priority(showParser) == 15
    @test showParser.initialState === none(Option{tstate(inner_obj)})
end

@testset "should parse a basic subcommand with arguments" begin
    showParser = cmd(
        "show",
        object(
            (
                type = @constant(:show),
                progress = gate("-p", "--progress"),
                id = arg(str()),
            )
        ),
    )

    val = parse_ok(showParser, ["show", "--progress", "item123"])
    @test val.type == Val(:show)
    @test val.progress == true
    @test val.id == "item123"
end

@testset "should suport aliases (multiple names)" begin
    showParser = cmd(
        "show", "sh",
        object(
            (
                type = @constant(:show),
                progress = gate("-p", "--progress"),
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
    showParser = cmd(
        "show",
        object(
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
    editParser = cmd(
        "edit",
        object(
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
    editParser = cmd(
        "edit",
        object(
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

@testset "should work with or() combinator for multiple subcommands" begin
    parser = or(
        cmd(
            "show",
            object(
                (
                    type = @constant(:show),
                    progress = gate("-p", "--progress"),
                    id = arg(str()),
                )
            ),
        ),
        cmd(
            "edit",
            object(
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
        cmd(
            "show",
            object(
                (
                    type = @constant(:show),
                    id = arg(str()),
                )
            ),
        ),
        cmd(
            "edit",
            object(
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
    showParser = cmd(
        "show",
        object(
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
        cmd(
            "show",
            object(
                (
                    type = @constant(:show),
                    progress = gate("-p", "--progress"),
                    id = arg(str()),
                )
            ),
        ),
        cmd(
            "edit",
            object(
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
        cmd(
            "test",
            object(
                (
                    type = @constant(:test),
                    id = arg(str()),
                )
            ),
        ),
        cmd(
            "testing",
            object(
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
    parser = cmd(
        "--help",
        object(
            (
                type = @constant(:help),
            )
        ),
    )

    val = parse_ok(parser, ["--help"])
    @test val.type == Val(:help)
end


@testset "should handle nested commands (command within object parser)" begin
    nestedParser = object(
        (
            globalFlag = gate("--global"),
            command = cmd(
                "run",
                object(
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

    command = val.command
    @test command.type == Val(:run)
    @test command.script == "build"
end

# @testset "should fail when command is used with tuple parser and insufficient elements" begin
#     tupleParser = tuple((
#         cmd("start", @constant(:start)),
#         arg(str()),
#     ))

#     res = argparse(tupleParser, ["start"])
#     @test is_error(res)
#     err = unwrap_error(res)
#     @test occursin("too few arguments", string(err))
# end

@testset "should handle options terminator with commands" begin
    parser = cmd(
        "exec",
        object((
            type = @constant(:exec),
            args = multiple(arg(str())),
        )),
    )

    # Test with -- to terminate options parsing
    val = parse_ok(parser, ["exec", "--", "--not-an-option", "arg1"])
    @test val.type == Val(:exec)
    @test val.args == ["--not-an-option", "arg1"]
end

@testset "should keep treating input after -- as positional once a command is selected" begin
    parser = cmd(
        "test",
        object((
            type = @constant(:test),
            args = multiple(arg(str())),
        )),
    )

    val = parse_ok(parser, ["test", "--", "-v", "hello"])
    @test val.type == Val(:test)
    @test val.args == ["-v", "hello"]
end

@testset "should handle commands with numeric names" begin
    parser = or(
        cmd("v1", @constant(:version1)),
        cmd("v2", @constant(:version2)),
    )

    val1 = parse_ok(parser, ["v1"])
    @test val1 == Val(:version1)

    val2 = parse_ok(parser, ["v2"])
    @test val2 == Val(:version2)
end

@testset "should handle empty command name gracefully" begin
    parser = cmd("", @constant(:empty))

    val = parse_ok(parser, [""])
    @test val == Val(:empty)
end
