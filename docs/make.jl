using Documenter
using OptParse

makedocs(
    sitename = "OptParse.jl Documentation",
    checkdocs = :exports,
    pages = [
        "index.md",
        "Examples" => "examples.md",
        "API Docstrings" => "reference.md",
        "Development" => [
            "Overview" => "development/index.md",
            "Runtime Model" => "development/runtime.md",
            "Parser Semantics" => "development/parsers.md",
            "Extending OptParse" => "development/extending.md",
            "Inference And Trimming" => "development/inference.md",
        ],
    ],
    modules = [OptParse]
)

deploydocs(
    repo = "github.com/ghyatzo/OptParse.jl.git",
    devbranch = "main",
)
