module HelloWorld

using OptParse

name_parser = option("-n", "--name", str("NAME"))


hello = @parser struct Hello
    "Name to greet"
    name = option("-n", "--name", str("NAME"))
end


goodbye = @parser struct Goodbye
    "Name to wave goodbye"
    name = name_parser
end

const p = or(command("hello", hello), command("goodbye", goodbye))

runaction(x::Hello) = println(Core.stdout, "Hello, $(x.name)!")
runaction(x::Goodbye) = println(Core.stdout, "Goodbye, $(x.name)!")

function (@main)(args::Vector{String})::Cint
    obj = optparse(p, args)
    isnothing(obj) && return 1

    runaction(obj)
    return 0
end

end # module HelloWorld



# using OptParse

const parser = @parser struct Option
    "gossamer formats Julia source code with a focus on fixing mistakes rather than enforcing a uniform style."

    "Do not write output and exit with a non-zero code if the input is not formatted correctly."
    check = flag("-c", "--check")

    """Print the diff between the input and formatted output to stderr.
    Requires `git` to be installed."""
    diff = flag("-d", "--diff")

    "Format files in place."
    inplace = flag("-i", "--inplace")

    """Limit formatting to the line range <start line> to <end line>. Multiple
    ranges can be formatted by specifying multiple --lines arguments."""
    lines = many(option("--lines", str("LINES")))

    """File to write formatted output to. If no output is given, or if the file
    is `-`, output is written to stdout."""
    output = optional(option(("-o", "--output"), str("OUTPUT")))

    "Assumed filename when formatting from stdin. Used for error messages."
    stdin_filename = optional(option("--stdin-filename", str("STDIN-FILENAME")))

    "Enable verbose output."
    verbose = flag("-v", "--verbose")

    "Print Gossamer and julia version information."
    version = flag("--version"),

    "HHSHS"
    files = many(arg(str("FILE")))
end


# function parse_options(args)
#     # Workaround for
#     # https://github.com/ghyatzo/OptParse.jl/issues/9. Can be removed
#     # once OptParse 0.3.1 is released.
#     isempty(args) && return optparse(parser, ["--"])

#     return runparse(parser, args)
# end

# const usage_help =
# """
# usage: gossamer [options] <path>...

# Options:
# NAME
#        gossamer - format Julia source code

# SYNOPSIS
#        gossamer [<options>] <path>...

# DESCRIPTION

#        gossamer formats Julia source code with a focus on fixing mistakes rather
#        than enforcing a uniform style.

# OPTIONS
#        <path>...
#            Input path(s) (files and/or directories) to process. For directories,
#            all files (recursively) with the '.jl' extension are used as input
#            files. If no path is given, or if path is `-`, input is read from stdin.

#        -c, --check
#            Do not write output and exit with a non-zero code if the input is not
#            formatted correctly.

#        -d, --diff
#            Print the diff between the input and formatted output to stderr.
#            Requires `git` to be installed.

#        -h, --help
#            Print this message.

#        -i, --inplace
#            Format files in place.

#        --lines=<start line>:<end line>
#            Limit formatting to the line range <start line> to <end line>. Multiple
#            ranges can be formatted by specifying multiple --lines arguments.

#        -o <file>, --output=<file>
#            File to write formatted output to. If no output is given, or if the file
#            is `-`, output is written to stdout.

#        --stdin-filename=<filename>
#            Assumed filename when formatting from stdin. Used for error messages.

#        -v, --verbose
#            Enable verbose output.

#        --version
#            Print Gossamer and julia version information.
# """
