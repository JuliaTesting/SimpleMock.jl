# SimpleMock [![Docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://juliatesting.github.io/SimpleMock.jl) [![CI](https://github.com/JuliaTesting/SimpleMock.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/JuliaTesting/SimpleMock.jl/actions/workflows/CI.yml)

### Notice: kind of broken

This package is [broken in some cases on Julia 1.6 and newer](https://github.com/JuliaTesting/SimpleMock.jl/issues/13), for unknown reasons.
Use at your own risk!

---

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
