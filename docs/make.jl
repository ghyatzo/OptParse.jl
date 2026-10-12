using Documenter
using OptParse

makedocs(
    sitename = "OptParse.jl Documentation",
    format = Documenter.HTML(; edit_link = "main"),
    checkdocs = :exports,
    pages = [
        "Getting started" => "index.md",
        "User guide" => "guide.md",
        "Examples" => "examples.md",
        "API reference" => "reference.md",
        "Migration guide" => "migration.md",
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
