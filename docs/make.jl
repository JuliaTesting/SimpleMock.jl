using SimpleMock
using Documenter

makedocs(;
    modules=[SimpleMock],
    authors="Chris de Graaf <chrisadegraaf@gmail.com>",
    repo="https://github.com/christopher-dG/SimpleMock.jl/blob/{commit}{path}#L{line}",
    sitename="SimpleMock.jl",
    format=Documenter.HTML(;
        canonical="https://christopher-dG.github.io/SimpleMock.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/christopher-dG/SimpleMock.jl",
)
