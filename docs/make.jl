using Documenter
using OptParse

makedocs(
    sitename = "OptParse.jl Documentation",
    pages = [
        "index.md",
        "Examples" => "examples.md",
        "API Docstrings" => "reference.md",
    ],
    # modules = [OptParse] # not yet ready to test docstrings
)
