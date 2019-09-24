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

const DEFAULT = gensym()
const SYMBOL = Ref(:_)

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
f(args...) = get(args...)
mock(get) do g
    f(1)  # Would normally throw a `MethodError` for `get`.
    @assert called_once_with(g, 1)
end
```

Mocking a function with a custom `Mock`:
```julia
f(args...) = get(args...)
mock(get => Mock(; return_value=1)) do g
    @assert f(1, 2, 3) == 1
    @assert called_once_with(g, 1, 2, 3)
end
```

Mocking with something other than a `Mock`:
```julia
f(x) = get(x)
mock(get => x -> 2x) do _g
    @assert f(2) == 4
end
```

## Reusing A `Context`

Under the hood, this function creates a new [Cassette `Context`](https://jrevels.github.io/Cassette.jl/stable/api.html#Cassette.Context) on every call by default.
This provides a nice clean mocking environment, but it can be slow to create and call new types and methods over and over.
If you find yourself repeatedly mocking the same set of functions, you can specify a context name to reuse that context like so:

```julia
julia> ctx = gensym();

# The first time is a bit slower.
julia> @time mock(g -> @assert(!called(g)), ctx, get)
  0.057888 seconds (101.74 k allocations: 5.742 MiB)

# But this one is fast!
julia> @time mock(g -> @assert(!called(g)), ctx, get)
  0.005509 seconds (5.23 k allocations: 258.584 KiB)
```

Be careful though!
If you call a function that you've previously mocked but are not currently mocking, you'll run into trouble:

```julia
julia> f(s) = strip(uppercase(s));
julia> ctx = gensym();

julia> mock(_g -> f(" hi "), ctx, strip);
julia> mock(_g -> f(" hi "), ctx, uppercase)
ERROR: KeyError: key strip not found
```
"""
function mock(f::Function, args...)
    name = SYMBOL[] = Symbol(SYMBOL[], :A)
    return mock(f, name, args...)
end

function mock(f::Function, ctx::Symbol, args...)
    mocks = Dict()  # Mapping of function => mock (or something from the  user).
    foreach(args) do arg
        if arg isa Pair
            mocks[arg.first] = arg.second
        else
            mocks[arg] = Mock()
        end
    end

    # Create the Context type if it doesn't already exist.
    ctx_is_new, Ctx = if isdefined(Contexts, ctx)
        false, getfield(Contexts, ctx)
    else
        true, @eval Contexts Cassette.@context $ctx
    end

    # Compute the function types to overdub.
    F = Union{map(typeof, collect(keys(mocks)))...}

    # Implement the overdub, but only if it's not already implemented.
    overdub_is_new = !overdub_exists(Ctx, F)
    if overdub_is_new
        @eval Contexts Cassette.overdub(ctx::$Ctx, f::$F, args...; kwargs...) =
            ctx.metadata[f](args...; kwargs...)
    end

    # Only use `invokelatest` if the Context/overdub implementations are new.
    c = ctx_is_new ? invokelatest(Ctx; metadata=mocks) : Ctx(; metadata=mocks)
    return if overdub_is_new
        invokelatest(overdub, c, f, values(mocks)...)
    else
        overdub(c, f, values(mocks)...)
    end
end

# Has a function (or Union of functions) already been overdubbed for a given Context?
overdub_exists(::Type{Ctx}, ::Type{F}) where {Ctx, F} = any(methods(overdub)) do m
    Ts = unwrap_unionall(m.sig).types
    length(Ts) >= 2 && Ts[2] === Ctx && Ts[3] === F
end

end
