using Documenter
using OptParse

makedocs(
    sitename = "OptParse.jl Documentation",
    checkdocs = :exports,
    pages = [
        "index.md",
        "Examples" => "examples.md",
        "API Docstrings" => "reference.md",
    ],
    modules = [OptParse]
)
