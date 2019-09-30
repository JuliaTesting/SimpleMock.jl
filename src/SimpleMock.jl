"""
A basic mocking module, inspired by Python's [`unittest.mock`](https://docs.python.org/3/library/unittest.mock.html) and implemented with [Cassette](https://github.com/jrevels/Cassette.jl).

## Usage

For usage examples, see [`mock`](@ref).

## Differences from `unittest.mock`

- SimpleMock only implements mocking of function calls, as opposed to arbitrary monkey-patching.
- Neither `getfield` nor `setfield!` is implemented for the default [`Mock`](@ref) type.
"""
module SimpleMock

using Base: Callable, invokelatest, unwrap_unionall
using Base.Iterators: Pairs

using Cassette: overdub

export
    Call,
    Mock,
    mock,
    calls,
    ncalls,
    called,
    called_once,
    called_with,
    called_once_with,
    has_call,
    has_calls,
    reset!

include("Contexts.jl")
include("mock_type.jl")
include("mock_fun.jl")

end
