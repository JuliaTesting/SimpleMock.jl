# SimpleMock [![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://christopher-dG.github.io/SimpleMock.jl/stable) [![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://christopher-dG.github.io/SimpleMock.jl/dev) [![Build Status](https://travis-ci.com/christopher-dG/SimpleMock.jl.svg?branch=master)](https://travis-ci.com/christopher-dG/SimpleMock.jl)

A basic mocking module, inspired by Python's [`unittest.mock`](https://docs.python.org/3/library/unittest.mock.html) and implemented with [Cassette](https://github.com/jrevels/Cassette.jl).

```jl
using SimpleMock

f(args...) = get(args...)

mock(get) do g
    f(1)  # Would normally throw a `MethodError` for `get`.
    @assert called_once_with(g, 1)
end
```
