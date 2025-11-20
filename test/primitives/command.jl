# This needs a couple of parsers still to be properly tested


@testset "should create a parser that matches a subcommand and applies inner parser" begin
    showParser = command(
        "show",
        object((
            type = constant("show"),
            progress = flag("-p", "--progress"),
            id = argument(str()),
        )),
    )

    @test getproperty(showParser, :priority) == 15
    @test getproperty(showParser, :initialState) === nothing
end

@testset "should parse a basic subcommand with arguments" begin
    showParser = command(
        "show",
        object((
            type = constant("show"),
            progress = flag("-p", "--progress"),
            id = argument(str()),
        )),
    )

    res = argparse(showParser, ["show", "--progress", "item123"])
    @test !is_error(res)

    # Value lives in next.state (Ok(...)); unwrap to get the parsed object
    val = unwrap(getproperty(unwrap(res).next, :state))
    @test getproperty(val, :type) == "show"
    @test getproperty(val, :progress) == true
    @test getproperty(val, :id) == "item123"
end

@testset "should fail when wrong subcommand is provided" begin
    showParser = command(
        "show",
        object((
            type = constant("show"),
            id = argument(str()),
        )),
    )

    res = argparse(showParser, ["edit", "item123"])
    @test is_error(res)
    err = unwrap_error(res)
    @test occursin("Expected command `show`", str(err))
end

@testset "should fail when subcommand is provided but required arguments are missing" begin
    editParser = command(
        "edit",
        object((
            type = constant("edit"),
            id = argument(str()),
        )),
    )

    res = argparse(editParser, ["edit"])
    @test is_error(res)
    err = unwrap_error(res)
    @test occursin("too few arguments", str(err))
end

@testset "should handle optional options in subcommands" begin
    editParser = command(
        "edit",
        object((
            type = constant("edit"),
            editor = optional(option("-e", "--editor", str())),
            id = argument(str()),
        )),
    )

    # Test with optional option
    res1 = argparse(editParser, ["edit", "-e", "vim", "item123"])
    @test !is_error(res1)
    val1 = unwrap(getproperty(unwrap(res1).next, :state))
    @test getproperty(val1, :type) == "edit"
    @test getproperty(val1, :editor) == "vim"
    @test getproperty(val1, :id) == "item123"

    # Test without optional option
    res2 = argparse(editParser, ["edit", "item456"])
    @test !is_error(res2)
    val2 = unwrap(getproperty(unwrap(res2).next, :state))
    @test getproperty(val2, :type) == "edit"
    @test getproperty(val2, :editor) === nothing
    @test getproperty(val2, :id) == "item456"
end

@testset "should work with or() combinator for multiple subcommands" begin
    parser = or(
        command(
            "show",
            object((
                type = constant("show"),
                progress = flag("-p", "--progress"),
                id = argument(str()),
            )),
        ),
        command(
            "edit",
            object((
                type = constant("edit"),
                editor = optional(option("-e", "--editor", str())),
                id = argument(str()),
            )),
        ),
    )

    # Test show command
    showRes = argparse(parser, ["show", "--progress", "item123"])
    @test !is_error(showRes)
    showVal = unwrap(getproperty(unwrap(showRes).next, :state))
    @test getproperty(showVal, :type) == "show"
    @test getproperty(showVal, :progress) == true
    @test getproperty(showVal, :id) == "item123"

    # Test edit command
    editRes = argparse(parser, ["edit", "-e", "vim", "item456"])
    @test !is_error(editRes)
    editVal = unwrap(getproperty(unwrap(editRes).next, :state))
    @test getproperty(editVal, :type) == "edit"
    @test getproperty(editVal, :editor) == "vim"
    @test getproperty(editVal, :id) == "item456"
end

@testset "should fail gracefully when no matching subcommand is found in or() combinator" begin
    parser = or(
        command(
            "show",
            object((
                type = constant("show"),
                id = argument(str()),
            )),
        ),
        command(
            "edit",
            object((
                type = constant("edit"),
                id = argument(str()),
            )),
        ),
    )

    res = argparse(parser, ["delete", "item123"])
    @test is_error(res)
    err = unwrap_error(res)
    @test occursin("Unexpected option or subcommand", str(err))
end

@testset "should handle empty input" begin
    showParser = command(
        "show",
        object((
            type = constant("show"),
            id = argument(str()),
        )),
    )

    res = argparse(showParser, String[])
    @test is_error(res)
    err = unwrap_error(res)
    @test occursin("end of input", str(err))
end

@testset "should provide correct type inference with InferValue" begin
    # or() of commands should behave like a union at runtime; we verify both branches.
    parser = or(
        command(
            "show",
            object((
                type = constant("show"),
                progress = flag("-p", "--progress"),
                id = argument(str()),
            )),
        ),
        command(
            "edit",
            object((
                type = constant("edit"),
                editor = optional(option("-e", "--editor", str())),
                id = argument(str()),
            )),
        ),
    )

    showRes = argparse(parser, ["show", "--progress", "item123"])
    editRes = argparse(parser, ["edit", "-e", "vim", "item456"])

    @test !is_error(showRes)
    @test !is_error(editRes)

    showVal = unwrap(getproperty(unwrap(showRes).next, :state))
    @test getproperty(showVal, :type) == "show"
    @test getproperty(showVal, :progress) == true
    @test getproperty(showVal, :id) == "item123"

    editVal = unwrap(getproperty(unwrap(editRes).next, :state))
    @test getproperty(editVal, :type) == "edit"
    @test getproperty(editVal, :editor) == "vim"
    @test getproperty(editVal, :id) == "item456"
end

@testset "should maintain type safety with complex nested objects" begin
    complexParser = command(
        "deploy",
        object((
            type = constant("deploy"),
            config = object((
                env = option("-e", "--env", str()),
                dryRun = flag("--dry-run"),
            )),
            targets = multiple(argument(str()); min = 1),
        )),
    )

    res = argparse(complexParser, ["deploy", "--env", "production", "--dry-run", "web", "api"])
    @test !is_error(res)

    val = unwrap(getproperty(unwrap(res).next, :state))
    @test getproperty(val, :type) == "deploy"

    cfg = getproperty(val, :config)
    @test getproperty(cfg, :env) == "production"
    @test getproperty(cfg, :dryRun) == true

    @test getproperty(val, :targets) == ["web", "api"]
end

# test/edge_command_tests.jl
using Test
using ErrorTypes
# using YourParserModule  # ← replace with your actual module if needed

@testset "should handle commands with same prefix names" begin
    parser = or(
        command(
            "test",
            object((
                type = constant("test"),
                id = argument(str()),
            )),
        ),
        command(
            "testing",
            object((
                type = constant("testing"),
                id = argument(str()),
            )),
        ),
    )

    # Should match "test" exactly, not "testing"
    res1 = argparse(parser, ["test", "item123"])
    @test !is_error(res1)
    val1 = unwrap(getproperty(unwrap(res1).next, :state))
    @test getproperty(val1, :type) == "test"

    # Should match "testing" exactly
    res2 = argparse(parser, ["testing", "item456"])
    @test !is_error(res2)
    val2 = unwrap(getproperty(unwrap(res2).next, :state))
    @test getproperty(val2, :type) == "testing"
end

@testset "should handle commands that look like options" begin
    parser = command(
        "--help",
        object((
            type = constant("help"),
        )),
    )

    res = argparse(parser, ["--help"])
    @test !is_error(res)
    val = unwrap(getproperty(unwrap(res).next, :state))
    @test getproperty(val, :type) == "help"
end

@testset "should handle command with array-like TState (state type safety test)" begin
    # multiple(flag("-v","--verbose")) returns an array-like state
    multiParser = command("multi", multiple(flag("-v", "--verbose")))

    res1 = argparse(multiParser, ["multi", "-v", "-v"])
    @test !is_error(res1)
    val1 = unwrap(getproperty(unwrap(res1).next, :state))
    @test val1 == [true, true]

    res2 = argparse(multiParser, ["multi"])
    @test !is_error(res2)
    val2 = unwrap(getproperty(unwrap(res2).next, :state))
    @test val2 == []
end

@testset "should handle nested commands (command within object parser)" begin
    nestedParser = object((
        globalFlag = flag("--global"),
        cmd = command(
            "run",
            object((
                type = constant("run"),
                script = argument(str()),
            )),
        ),
    ))

    res = argparse(nestedParser, ["--global", "run", "build"])
    @test !is_error(res)
    val = unwrap(getproperty(unwrap(res).next, :state))
    @test getproperty(val, :globalFlag) == true

    cmd = getproperty(val, :cmd)
    @test getproperty(cmd, :type) == "run"
    @test getproperty(cmd, :script) == "build"
end

@testset "should fail when command is used with tuple parser and insufficient elements" begin
    tupleParser = tuple((
        command("start", constant("start")),
        argument(str()),
    ))

    res = argparse(tupleParser, ["start"])
    @test is_error(res)
    err = unwrap_error(res)
    @test occursin("too few arguments", str(err))
end

@testset "should handle options terminator with commands" begin
    parser = command(
        "exec",
        object((
            type = constant("exec"),
            args = multiple(argument(str())),
        )),
    )

    # Test with -- to terminate options parsing
    res = argparse(parser, ["exec", "--", "--not-an-option", "arg1"])
    @test !is_error(res)
    val = unwrap(getproperty(unwrap(res).next, :state))
    @test getproperty(val, :type) == "exec"
    @test getproperty(val, :args) == ["--not-an-option", "arg1"]
end

@testset "should handle commands with numeric names" begin
    parser = or(
        command("v1", constant("version1")),
        command("v2", constant("version2")),
    )

    res1 = argparse(parser, ["v1"])
    @test !is_error(res1)
    val1 = unwrap(getproperty(unwrap(res1).next, :state))
    @test val1 == "version1"

    res2 = argparse(parser, ["v2"])
    @test !is_error(res2)
    val2 = unwrap(getproperty(unwrap(res2).next, :state))
    @test val2 == "version2"
end

@testset "should handle empty command name gracefully" begin
    parser = command("", constant("empty"))

    res = argparse(parser, [""])
    @test !is_error(res)
    val = unwrap(getproperty(unwrap(res).next, :state))
    @test val == "empty"
end