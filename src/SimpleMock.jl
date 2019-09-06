module SimpleMock

using Base: Callable, invokelatest
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
struct Mock{S, R}
    id::Symbol
    calls::Vector{Call}
    vars::Dict{Symbol, Any}
    effect::S
    ret::R
end

Mock(; return_value::R=DEFAULT, side_effect::S=nothing) where {S, R} =
    Mock{S, R}(gensym(), [], Dict(), side_effect, return_value)

Base.:(==)(a::Mock, b::Mock) = getfield(a, :id) === getfield(b, :id)
Base.getproperty(m::Mock, s::Symbol) = get!(Mock, getfield(m, :vars), s)
Base.show(io::IO, ::MIME"text/plain", m::Mock) = print(io, "Mock(id=$(getfield(m, :id)))")

"""
    (m::Mock)(args...; kwargs...)

Calling a `Mock` triggers its `side_effect` or returns its `return_value`.
If neither are configured, a brand new `Mock` is returned.

Either way, the call is recorded in the original `Mock`'s history.
"""
function (m::Mock)(args...; kwargs...)
    push!(calls(m), Call(args...; kwargs...))

    effect = getfield(m, :effect)
    effect isa Vector && (effect = popfirst!(effect))
    effect isa Exception && throw(effect)
    effect isa Callable && effect(args...; kwargs...)  # TODO: Arbitrary callable types.
    effect === nothing || return effect

    ret = getfield(m, :ret)
    return ret === DEFAULT ? Mock() : ret
end

"""
    calls(::Mock) -> Vector{Call}

Return the call history of the [`Mock`](@ref).
"""
calls(m::Mock) = getfield(m, :calls)

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
    # TODO: Is this the best way to do it? Basically slide a window across the call list.
    existing = calls(m)
    isempty(cs) && return true
    length(cs) > ncalls(m) && return false
    cs = collect(cs)  # Omitting this causes a segfault?!
    n = length(cs) - 1
    for i in 1:(ncalls(m) - n)
        existing[i:i+n] == cs && return true
    end
    return false
end

"""
    reset!(::Mock)

Reset a [`Mock`](@ref)'s call history and internal variables.
Side effects and return values are preserved.
"""
reset!(m::Mock) = (empty!(calls(m)); empty!(getfield(m, :vars)))

"""
    mock(f::Function[, ctx::Symbol], args...)

Run `f` with specified functions replaced with [`Mock`](@ref)s.

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

    # TODO: Check for an existing method.
    @eval Contexts Cassette.overdub(ctx::$Ctx, f::$F, args...; kwargs...) =
        ctx.metadata[f](args...; kwargs...)

    # We use `invokelatest` since we've only just created the functions we need to call.
    c = invokelatest(Ctx; metadata=Dict(zip(funcs, mocks)))
    invokelatest(overdub, c, f, mocks...)
end

end
