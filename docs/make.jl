using ICARE, Documenter, Changelog

# Generate a Documenter-friendly changelog from CHANGELOG.md
Changelog.generate(
    Changelog.Documenter(),
    joinpath(@__DIR__, "..", "CHANGELOG.md"),
    joinpath(@__DIR__, "src", "release-notes.md");
    repo = "LIM-AeroCloud/ICARE.jl",
)

# Build documentation
makedocs(
    # modules=[ICARE],
    authors="Peter Bräuer <pb866.git@gmail.com> and contributors",
    sitename="ICARE.jl Documentation",
    checkdocs=:public,
    format=Documenter.HTML(;
        prettyurls=false,
        canonical="https://LIM-AeroCloud.github.io/ICARE.jl",
        edit_link="dev",
        assets=String["assets/favicon.ico"],
    ),
    pages=[
        "Home" => "index.md",
        "Release notes" => "release-notes.md",
        # "Index" => "register.md"
    ]
)

deploydocs(
    repo = "github.com/LIM-AeroCloud/ICARE.jl.git",
    devbranch="dev"
)
