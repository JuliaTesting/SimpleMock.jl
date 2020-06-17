using SimpleMock
using Documenter

makedocs(;
    modules=[SimpleMock],
    authors="Chris de Graaf <me@cdg.dev>",
    repo="https://github.com/JuliaTesting/SimpleMock.jl/blob/{commit}{path}#L{line}",
    sitename="SimpleMock.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://juliatesting.github.io/SimpleMock.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/JuliaTesting/SimpleMock.jl",
)
