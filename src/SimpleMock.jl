"""
A basic mocking module, inspired by Python's
[`unittest.mock`](https://docs.python.org/3/library/unittest.mock.html)
and implemented with
[Cassette](https://github.com/jrevels/Cassette.jl).
"""
module SimpleMock

using Base: Callable, invokelatest, kwarg_decl
using Base.Iterators: Pairs
using Core: kwftype

using Cassette: Cassette, overdub, @context

export
    Call,
    Mock,
    mock,
    calls,
    last_call,
    ncalls,
    called,
    called_once,
    called_with,
    called_last_with,
    called_once_with,
    has_call,
    has_calls,
    reset!

include("mock_type.jl")
include("mock_fun.jl")

end
