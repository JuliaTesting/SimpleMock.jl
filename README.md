# SimpleMock [![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://christopher-dG.github.io/SimpleMock.jl/stable) [![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://christopher-dG.github.io/SimpleMock.jl/dev) [![Build Status](https://travis-ci.com/christopher-dG/SimpleMock.jl.svg?branch=master)](https://travis-ci.com/christopher-dG/SimpleMock.jl)

A basic mocking module, inspired by Python's [`unittest.mock`](https://docs.python.org/3/library/unittest.mock.html) and implemented with [Cassette](https://github.com/jrevels/Cassette.jl).

```jl
using SimpleMock

f(x) = x + 1
mock(+) do plus
    @assert plus isa Mock
    @assert f(0) != 1  # The call to + is mocked.
    @assert called_once_with(plus, 0, 1)
end

mock((+, Float64, Float64) => Mock((a, b) -> 2a + 2b)) do plus
    @assert 1 + 1 == 2
    @assert 2.0 + 2.0 == 8
    @assert called_once_with(plus, 2.0, 2.0)
end
```

See the documentation for more details and examples.
