using OptParse


# -----------------------------------------------------------------------------
# cli/globals.jl
# -----------------------------------------------------------------------------

const globalhelp = help(
    "Global options",
    description = """
    Options that apply before the subcommand is selected.

    These are the knobs you would typically place before the command name in a
    git-style CLI.
    """
)

const globoptions = record((;
    cwd      = option("-C", str("PATH"))      |> help("Working directory") |> many(),
    config   = option("-c", str("KEY=VALUE")) |> help("Config override")   |> many(),
    paginate = flag("-p", "--paginate")       |> help("Paginate"),
    nopager  = flag("-P", "--no-pager")       |> help("No pager"),
    version  = flag("--version")              |> help("Version"),
)) |> globalhelp


# -----------------------------------------------------------------------------
# cli/commands/status.jl
# -----------------------------------------------------------------------------

const status_untracked =
    option("-u", "--untracked-files", choice(["all", "normal", "no"])) |>
    help(
        "Untracked files",
        description = "Choose whether untracked files are shown in full, shown in the normal condensed form, or hidden entirely."
    ) |>
    optional()

const status_ignored =
    option("--ignored", choice(["traditional", "matching", "no"])) |>
    help("Ignored files") |>
    optional()

const statushelp = help(
    "Status",
    description = """
    Show the working tree status.

    This command reports staged, unstaged, and untracked changes. It can also be
    restricted to a set of pathspecs.
    """
)

const statuscmd = record((;
    short      = flag("-s", "--short")     |> help("Short"),
    branch     = flag("-b", "--branch")    |> help("Branch"),
    porcelain  = flag("--porcelain")       |> help("Porcelain"),
    untracked  = status_untracked,
    ignored    = status_ignored,
    pathspecs  = arg(str("PATHSPEC"))      |> help("Pathspec") |> many(),
)) |> statushelp


# -----------------------------------------------------------------------------
# cli/commands/add.jl
# -----------------------------------------------------------------------------

const addhelp = help(
    "Add",
    description = """
    Add file contents to the index.

    The command accepts one or more pathspecs and can be asked to update only
    tracked files, stage everything, or interactively select hunks.
    """
)

const addcmd = record((;
    dryrun    = flag("-n", "--dry-run")    |> help("Dry run"),
    verbose   = flag("-v", "--verbose")    |> help("Verbose") |> many(),
    patch     = flag("-p", "--patch")      |> help("Patch"),
    force     = flag("-f", "--force")      |> help("Force"),
    update    = flag("-u", "--update")     |> help("Update"),
    all       = flag("-A", "--all")        |> help("All"),
    pathspecs = arg(str("PATHSPEC"))       |> help("Pathspec") |> many(),
)) |> addhelp


# -----------------------------------------------------------------------------
# cli/commands/commit.jl
# -----------------------------------------------------------------------------

const commit_message =
    option("-m", "--message", str("MSG")) |>
    help(
        "Message",
        description = "Use MSG as the commit message instead of opening an editor."
    )

const commit_message_file =
    option("-f", "--file", str("FILE")) |>
    help(
        "Message file",
        description = "Read the commit message from FILE."
    )

const commit_message_source =
    or(commit_message, commit_message_file) |>
    help(
        "Message source",
        description = "Choose whether the commit message is provided inline or read from a file."
    ) |>
    optional()

const commit_author =
    option("--author", str("AUTHOR")) |>
    help("Author") |>
    optional()

const commit_date =
    option("--date", str("DATE")) |>
    help("Date") |>
    optional()

const commithelp = help(
    "Commit",
    description = """
    Record the staged contents as a new commit.

    This variant keeps the shape intentionally compact while still stressing
    mutually exclusive inputs, optional metadata, and boolean mode flags.
    """,
    footer = """
    Examples:
      gitlike commit -m "initial import"
      gitlike commit --amend --author "Example <dev@example.com>"
    """
)

const commitcmd = record((;
    message_file = commit_message_source,
    all          = flag("-a", "--all")        |> help("All"),
    amend        = flag("--amend")            |> help("Amend"),
    signoff      = flag("-s", "--signoff")    |> help("Signoff"),
    author       = commit_author,
    date         = commit_date, # todo: add date/time value parsers
    empty        = flag("--allow-empty")      |> help("Allow empty"),
)) |> commithelp


# -----------------------------------------------------------------------------
# cli/commands/clone.jl
# -----------------------------------------------------------------------------

const clone_branch =
    option("-b", "--branch", str("BRANCH")) |>
    help(
        "Branch",
        description = "Check out BRANCH after cloning instead of the remote's default branch."
    ) |>
    optional()

const clone_depth =
    option("-d", "--depth", integer("DEPTH")) |>
    help(
        "Depth",
        description = "Create a shallow clone containing only DEPTH commits of history."
    ) |>
    optional()

const clone_origin =
    option("-o", "--origin", str("NAME")) |>
    help("Origin name") |>
    optional()

const clone_dir =
    arg(str("DIR")) |>
    help("Directory") |>
    optional()

const clonehelp = help(
    "Clone",
    description = """
    Clone a repository into a new directory.

    This command mixes repeated flags, optional value options, and positional
    arguments in a shape that is representative of a real-world CLI.
    """,
    footer = """
    Examples:
      gitlike clone https://example/repo.git
      gitlike clone -b main --depth 10 https://example/repo.git worktree
    """
)

const clonecmd = record((;
    quiet        = flag("-q", "--quiet")            |> help("Quiet"),
    verbose      = flag("-v", "--verbose")          |> help("Verbose") |> many(),
    branch       = clone_branch,
    depth        = clone_depth,
    singlebranch = flag("--single-branch")          |> help("Single branch"),
    bare         = flag("--bare")                   |> help("Bare"),
    origin       = clone_origin,
    repo         = arg(str("REPO"))                 |> help("Repository"),
    dir          = clone_dir,
)) |> clonehelp


# -----------------------------------------------------------------------------
# cli/commands/push.jl
# -----------------------------------------------------------------------------

const push_forcelease =
    flag("--force-with-lease") |>
    help(
        "Force with lease",
        description = "Force-push only if the remote ref still points to the value you expect."
    )

const push_repo =
    arg(str("REPO")) |>
    help("Repository") |>
    optional()

const pushhelp = help(
    "Push",
    description = """
    Update remote refs along with the objects needed to support them.

    This command is useful for checking how larger option sets render in help,
    especially when some of those options are safety-sensitive.
    """
)

const pushcmd = record((;
    upstream   = flag("-u", "--set-upstream") |> help("Set upstream"),
    force      = flag("-f", "--force")        |> help("Force"),
    forcelease = push_forcelease,
    tags       = flag("--tags")               |> help("Tags"),
    all        = flag("--all")                |> help("All"),
    dryrun     = flag("-n", "--dry-run")      |> help("Dry run"),
    repo       = push_repo,
    refspecs   = arg(str("REFSPEC"))          |> help("Refspec") |> many(),
)) |> pushhelp


# -----------------------------------------------------------------------------
# cli/commands/remote.jl
# -----------------------------------------------------------------------------

const remote_add_branches =
    option("-t", str("BRANCH")) |>
    help("Tracked branch") |>
    many()

const remote_add_tag_policy =
    or(
        flag("--tags")    |> help("Import tags"),
        flag("--no-tags") |> help("Disable tag import"),
    ) |>
    help(
        "Tag policy",
        description = "Choose whether tags are imported automatically for the newly added remote."
    )

const remote_addhelp = help(
    "Remote add",
    description = """
    Create a new remote and optionally fetch it immediately.

    This subcommand is intentionally a bit denser than the others so the help
    system has something realistic to render.
    """
)

const remote_add = record((;
    fetch    = flag("-f", "--fetch")   |> help("Fetch"),
    branches = remote_add_branches,
    tags     = remote_add_tag_policy,
    name     = arg(str("NAME"))        |> help("Name"),
    url      = arg(str("URL"))         |> help("URL"), # todo: add URL value parser
)) |> remote_addhelp

const remote_remove =
    arg(str("NAME")) |>
    help("Remote name") |>
    help(
        "Remote remove",
        description = "Remove a configured remote."
    )

const remote_geturlhelp = help(
    "Remote get-url",
    description = """
    Display one or more URLs configured for a remote.
    """
)

const remote_geturl = record((
    push = flag("--push")              |> help("Push URL"),
    all  = flag("--all")               |> help("All URLs"),
    name = arg(str("NAME"))            |> help("Remote name"),
)) |> remote_geturlhelp

const remote_seturl_oldurl =
    arg(str("OLDURL")) |>
    help("Old URL") |>
    optional()

const remote_seturlhelp = help(
    "Remote set-url",
    description = """
    Change the URLs configured for a remote.
    """
)

const remote_seturl = record((
    push   = flag("--push")            |> help("Push URL"),
    name   = arg(str("NAME"))          |> help("Remote name"),
    newurl = arg(str("NEWURL"))        |> help("New URL"),
    oldurl = remote_seturl_oldurl,
)) |> remote_seturlhelp

const remote_rename = sequence(
    arg(str("OLD")) |> help("Old name"),
    arg(str("NEW")) |> help("New name"),
)

const remotehelp = help(
    "Remote",
    description = """
    Manage the set of tracked repositories.

    This nested command family is the part of the example that most closely
    stresses focused help generation and nested command rendering.
    """,
    footer = """
    Examples:
      gitlike remote add origin https://example/repo.git
      gitlike remote set-url origin https://example/new.git
    """
)

const remotecmd = record((
    verbose = flag("-v", "--verbose")  |> help("Verbose") |> many(),
    subcmd  = or(
        command("add",     remote_add)     |> help("Add a new remote"),
        command("rename",  remote_rename)  |> help("Rename an existing remote"),
        command("remove",  remote_remove)  |> help("Remove an existing remote"),
        command("get-url", remote_geturl)  |> help("Show remote URLs"),
        command("set-url", remote_seturl)  |> help("Change remote URLs"),
    ),
)) |> remotehelp


# -----------------------------------------------------------------------------
# cli/root.jl
# -----------------------------------------------------------------------------

const gitlikehelp = help(
    "Gitlike",
    description = """
    A non-trivial git-inspired CLI used to stress OptParse parsing, help
    generation, and trimming.

    The example intentionally mixes global options, nested subcommands, repeated
    arguments, and mutually exclusive groups.
    """,
    footer = """
    Examples:
      gitlike status --short
      gitlike commit -m "initial import"
      gitlike remote add origin https://example/repo.git
    """
)

const parser = record((
    options = globoptions,
    cmd     = or(
        command("status", statuscmd)  |> help("Show working tree status"),
        command("add",    addcmd)     |> help("Add file contents to the index"),
        command("commit", commitcmd)  |> help("Record changes to the repository"),
        command("clone",  clonecmd)   |> help("Clone a repository into a new directory"),
        command("push",   pushcmd)    |> help("Update remote refs"),
        command("remote", remotecmd)  |> help("Manage configured remotes"),
    ),
)) |> gitlikehelp


function @main(args::Vector{String})::Cint
    res = optparse(parser, args)
    isnothing(res) && return 1

    println(Core.stdout, "OPTIONS")
    doaction(res.cmd)

    return 0
end

function doaction(obj::resulttype(remotecmd))
    print(Core.stdout, "REMOTE CMD")
end

function doaction(obj)
    print(Core.stdout, "EVERYTHING ELSE")
end


# Help examples:
#
# print(generate_help(parser, String[]; progname = "gitlike"))
# print(generate_help(parser, ["commit"]; progname = "gitlike"))
# print(generate_help(parser, ["clone"]; progname = "gitlike"))
# print(generate_help(parser, ["remote"]; progname = "gitlike"))
# print(generate_help(parser, ["remote", "add"]; progname = "gitlike"))
