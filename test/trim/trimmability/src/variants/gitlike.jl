using OptParse

const globoptions = object((;

	cwd = option("-C", str("PATH"))
		|> help("changes working directory before running the command")
		|> multiple(),

	config = option("-c", str("KEY=VALUE")) # todo: pair value parsers
		|> help("inline config override")
		|> multiple(),

	paginate = flag("-p", "--paginate") |> help("forces pagination"),
	nopager = flag("-P", "--no-pager") |> help("disables the pager"),

	version = flag("--version") |> help("prints the version")
))

const statuscmd = object((;
	short = 		flag("-s", "--short"),
	branch = 		flag("-b", "--branch"),
	porcelain = 	flag("--porcelain"),

	untracked = 	option("-u", "--untracked-files", choice(["all", "normal", "no"]))
		|> optional(),
	ignored = 		option("--ignored", choice(["traditional", "matching", "no"]))
		|> optional(),
	pathspecs = 	arg(str("PATHSPEC"))
		|> multiple()
))

const addcmd = object((;
	dryrun = flag("-n", "--dry-run"),
	verbose = flag("-v", "--verbose") |> multiple(),
	patch = flag("-p", "--patch"),
	force = flag("-f", "--force"),
	update = flag("-u", "--update"),
	all = flag("-A", "--all"),

	pathspecs = arg(str("PATHSPEC")) |> multiple()
))



const commitcmd = object((;

	message_file = or(
		option("-m", "--message", str("MSG")),
		option("-f", "--file", str("FILE"))
	) |> optional(),

	all = flag("-a", "--all"),
	amend = flag("--amend"),
	signoff = flag("-s", "--signoff"),
	author = option("--author", str("AUTHOR")) |> optional(),
	date = option("--date", str("DATE")) |> optional(), # todo add date time value parsers
	empty = flag("--allow-empty")
))



const clonecmd = object((;
	quiet = flag("-q", "--quiet"),
	verbose = flag("-v", "--verbose") |> multiple(),
	branch = option("-b", "--branch", str("BRANCH")) |> optional(),
	depth = option("-d", "--depth", integer("DEPTH")) |> optional(),
	singlebranch = flag("--single-branch"),
	bare = flag("--bare"),
	origin = option("-o", "--origin", str("NAME")) |> optional(),

	repo = arg(str("REPO")),
	dir = arg(str("DIR")) |> optional()
))




const pushcmd = object((;
	upstream = flag("-u", "--set-upstream"),
	force = flag("-f", "--force"),
	forcelease = flag("--force-with-lease"),
	tags = flag("--tags"),
	all = flag("--all"),
	dryrun = flag("-n", "--dry-run"),

	repo = arg(str("REPO")) |> optional(),
	refspecs = arg(str("REFSPEC")) |> multiple()
))


const remote_add = object((;
	fetch = flag("-f", "--fetch"),
	branches = option("-t", str("BRANCH")) |> multiple(),
	tags = or(
		flag("--tags"),
		flag("--no-tags")
	),

	name = arg(str("NAME")),
	url = arg(str("URL")) # todo add url value parser
))

const remote_remove = arg(str("NAME"))

const remote_geturl = object((
	push = flag("--push"),
	all = flag("--all"),
	name = arg(str("NAME"))
))

const remote_seturl = object((
	push = flag("--push"),
	name = arg(str("NAME")),
	newurl = arg(str("NEWURL")),
	oldurl = arg(str("OLDURL")) |> optional()
))

const remotecmd = object((
	verbose = flag("-v", "--verbose") |> multiple(),
	subcmd = or(
		command("add", remote_add),
		command("rename", sequence(arg(str("OLD")), arg(str("NEW")))),
		command("remove", arg(str("NAME"))),
		command("get-url", remote_geturl),
		command("set-url", remote_seturl)
	)
))


const parser = object((
	options = globoptions,
	cmd = or(
		command("status", statuscmd),
		command("add", addcmd),
		command("commit", commitcmd),
		command("clone", clonecmd),
		command("push", pushcmd),
		command("remote", remotecmd),
	)
))

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
