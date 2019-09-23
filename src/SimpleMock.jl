"""
A basic mocking module, inspired by Python's [`unittest.mock`](https://docs.python.org/3/library/unittest.mock.html) and implemented with [Cassette](https://github.com/jrevels/Cassette.jl).

## Usage

For usage examples, see [`mock`](@ref).

## Differences from `unittest.mock`

- SimpleMock only implements mocking of function calls, as opposed to arbitrary monkey-patching.
- Neither `getfield` nor `setfield!` is not implemented for the default [`Mock`](@ref) object.
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

const DEFAULT = gensym()
const SYMBOL = Ref{Symbol}(:_)

module Contexts
using Cassette: Cassette
end

"""
    Call(args...; kwargs...)

Represents a function call.
"""
struct Call
    args::Tuple
    kwargs::Pairs

    Call(args...; kwargs...) = new(args, kwargs)
end

Base.:(==)(a::Call, b::Call) = a.args == b.args && a.kwargs == b.kwargs

"""
    Mock(; return_value=Mock(), side_effect=nothing)

Create a new mocking object, which behaves similarly to Python's [`Mock`](https://docs.python.org/3/library/unittest.mock.html#unittest.mock.Mock).

## Return Value
Use the `return_value` keyword to set the value to be returned upon calling the mock.
By default, the return value is a new `Mock`.

## Side Effects
Use the `side_effect` keyword to set a side effect to occur upon calling the mock.
- If the value is an `Exception`, then the exception is thrown.
- If the value is a function, then it is called with the same arguments and keywords.
- If the value is a `Vector`, then each call uses the next element.
- Any other value is returned without modification.
"""
struct Mock{R, S}
    id::Symbol
    calls::Vector{Call}
    ret::R
    effect::S
end

Mock(; return_value::R=DEFAULT, side_effect::S=nothing) where {R, S} =
    Mock{R, S}(gensym(), [], return_value, side_effect)

Base.:(==)(a::Mock, b::Mock) = a.id === b.id
Base.show(io::IO, ::MIME"text/plain", m::Mock) = print(io, "Mock(id=$(m.id))")

"""
    (m::Mock)(args...; kwargs...)

Calling a `Mock` triggers its `side_effect` or returns its `return_value` (in that order of priority).
If neither are configured, a brand new `Mock` is returned.

Either way, the call is recorded in the original `Mock`'s history.
"""
function (m::Mock)(args...; kwargs...)
    push!(calls(m), Call(args...; kwargs...))

    effect = m.effect
    effect isa Vector && (effect = popfirst!(effect))
    effect isa Exception && throw(effect)
    effect isa Callable && return effect(args...; kwargs...)  # TODO: Arbitrary callable types.
    effect === nothing || return effect

    return m.ret === DEFAULT ? Mock() : m.ret
end

"""
    calls(::Mock) -> Vector{Call}

Return the call history of the [`Mock`](@ref).
"""
calls(m::Mock) = m.calls

"""
    ncalls(::Mock) -> Int

Return the number of times that the [`Mock`](@ref) has been called.
"""
ncalls(m::Mock) = length(calls(m))

"""
    called(::Mock) -> Bool

Return whether or not the [`Mock`](@ref) has been called.
"""
called(m::Mock) = !isempty(calls(m))

"""
    called_once(::Mock) -> Bool

Return whether or not the [`Mock`](@ref) has been called exactly once.
"""
called_once(m::Mock) = length(calls(m)) == 1

"""
    called_with(::Mock, args...; kwargs...) -> Bool

Return whether or not the [`Mock`](@ref) has been called with the given arguments.
"""
called_with(m::Mock, args...; kwargs...) = has_call(m, Call(args...; kwargs...))

"""
    called_once_with(::Mock, args...; kwargs...) -> Bool

Return whether or not the [`Mock`](@ref) has been called exactly once with the given arguments.
"""
called_once_with(m::Mock, args...; kwargs...) =
    called_once(m) && called_with(m, args...; kwargs...)

"""
    has_call(::Mock, ::Call) -> Bool

Similiar to [`called_with`](@ref), but using a [`Call`](@ref).
"""
has_call(m::Mock, c::Call) = c in calls(m)

"""
    has_calls(::Mock, ::Calls...) -> Bool

Return whether or not the [`Mock`](@ref) has a particular ordered sequence of [`Call`](@ref)s.
"""
function has_calls(m::Mock, cs::Call...)
    isempty(cs) && return true
    existing = calls(m)
    length(cs) > length(existing) && return false
    cs = collect(cs)  # Omitting this causes a segfault?!
    n = length(cs) - 1
    for i in 1:(length(existing) - n)
        existing[i:i+n] == cs && return true
    end
    return false
end

"""
    reset!(::Mock)

Reset a [`Mock`](@ref)'s call history and internal variables.
Side effects and return values are preserved.
"""
reset!(m::Mock) = empty!(m.calls)

"""
    mock(f::Function[, ctx::Symbol], args...)

Run `f` with specified functions replaced with [`Mock`](@ref)s.

!!! warning
    There are a few issues with this function, see them on [GitHub](https://github.com/christopher-dG/SimpleMock.jl/issues?q=is%3Aissue+is%3Aopen+label%3A%22Function%3A+mock%22).

## Examples

Mocking a single function:

```julia
mock(get) do get
    Base.get(1)  # Would normally throw a `MethodError`.
    @assert called_once_with(get, 1)
end
```

Mocking a function with a custom `Mock`:
```julia
mock(get => Mock(; return_value=1)) do get
    @assert Base.get(1) == 1
    @assert called_once_with(get, 1)
end
```

## Reusing A `Context`

**TODO**: doc about reusing `Context` types.
"""
function mock(f::Function, args...)
    name = SYMBOL[] = Symbol(SYMBOL[], :A)
    return mock(f, name, args...)
end

function mock(f::Function, ctx::Symbol, args...)
    funcs = []  # Functions to be mocked.
    mocks = []  # Corresponding Mock objects (or anything else, really).
    foreach(args) do arg
        if arg isa Pair
            push!(funcs, arg.first)
            push!(mocks, arg.second)
        else
            push!(funcs, arg)
            push!(mocks, Mock())
        end
    end

    # Create the Context type if it doesn't already exist.
    isdefined(Contexts, ctx) || @eval Contexts Cassette.@context $ctx
    Ctx = getfield(Contexts, ctx)

    # Compute the function types to overdub.
    F = Union{map(typeof, funcs)...}

    # Implement the overdub, but only if it's not already implemented.
    if !overdub_exists(Ctx, F)
        @eval Contexts Cassette.overdub(ctx::$Ctx, f::$F, args...; kwargs...) =
            ctx.metadata[f](args...; kwargs...)
    end

    # We use `invokelatest` since we've only just created the functions we need to call.
    c = invokelatest(Ctx; metadata=Dict(zip(funcs, mocks)))
    return invokelatest(overdub, c, f, mocks...)
end

# Has a function (or Union of functions) already been overdubbed for a given Context?
overdub_exists(::Type{Ctx}, ::Type{F}) where {Ctx, F} = any(methods(overdub)) do m
    Ts = unwrap_unionall(m.sig).types
    length(Ts) >= 2 && Ts[2] === Ctx && Ts[3] === F
end

end
