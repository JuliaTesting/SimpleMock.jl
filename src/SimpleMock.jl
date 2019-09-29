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
reset!(m::Mock) = (empty!(m.calls); m)

"""
    mock(f::Function[, ctx::Symbol], args...)

Run `f` with specified functions mocked out.

## Examples

Mocking a single function:

```julia
mock(print) do print
    @assert print isa Mock
    println("!")  # This won't output anything.
    @assert called_once_with(print, stdout, "!", '\\n')
end
```

Mocking a function with a custom [`Mock`](@ref):

```julia
mock((+) => Mock(; return_value=1)) do plus
    @assert 1 + 1 == 1
    @assert called_once_with(plus, 1, 1)
end
```

Mocking methods that match a given signature:

```julia
mock((+, Float64, Float64) => Mock(; side_effect=(a, b) -> 2a + 2b)) do plus
    @assert 1 + 1 == 2
    @assert 2.0 + 2.0 == 8
    @assert called_once_with(plus, 2.0, 2.0)
end
```

Mocking with something other than a `Mock`:

```julia
mock((+) => (a, b) -> 2a + 2b) do _plus
    @assert 1 + 2 == 6
end
```

## Reusing A `Context`

Under the hood, this function creates a new [Cassette `Context`](https://jrevels.github.io/Cassette.jl/stable/api.html#Cassette.Context) on every call by default.
This provides a nice clean mocking environment, but it can be slow to create and call new types and methods over and over.
If you find yourself repeatedly mocking the same set of functions, you can specify a context name to reuse that context like so:

```julia
julia> ctx = gensym();

# The first time takes a little while.
julia> @time mock(g -> @assert(!called(g)), ctx, get)
  0.156221 seconds (171.93 k allocations: 9.356 MiB)

# But the next time is faster!
julia> @time mock(g -> @assert(!called(g)), ctx, get)
  0.052324 seconds (27.38 k allocations: 1.437 MiB)
```

Be careful though!
If you call a function that you've previously mocked but are not currently mocking, you'll run into trouble:

```julia
julia> f(s) = strip(uppercase(s));
julia> ctx = gensym();

julia> mock(_g -> f(" hi "), ctx, strip);
julia> mock(_g -> f(" hi "), ctx, uppercase)
ERROR: KeyError: key (strip, Vararg{Any,N} where N) not found
```
"""
function mock end

function mock(f::Function, args...)
    name = SYMBOL[] = Symbol(SYMBOL[], :A)
    return mock(f, name, args...)
end

function mock(f::Function, ctx::Symbol, args...)
    mocks = map(sig2mock, args)  # ((f, sig) => mock).

    # Create the Context type if it doesn't already exist.
    ctx_is_new, Ctx = if isdefined(Contexts, ctx)
        false, getfield(Contexts, ctx)
    else
        true, @eval Contexts Cassette.@context $ctx
    end

    # Implement the overdub, but only if it's not already implemented.
    overdub_is_new = any(map(first, mocks)) do k
        fun = k[1]
        sig = k[2:end]

        if overdub_exists(Ctx, fun, sig)
            false
        else
            make_overdub(Ctx, fun, sig)
            true
        end
    end

    # Only use `invokelatest` if the Context/overdub implementations are new.
    mocks_d = Dict(mocks)
    c = ctx_is_new ? invokelatest(Ctx; metadata=mocks_d) : Ctx(; metadata=mocks_d)
    od_args = [c, f, map(last, mocks)...]
    return overdub_is_new ? invokelatest(overdub, od_args...) : overdub(od_args...)
end

# Output (f, sig) => mock.
sig2mock(p::Pair{<:Tuple}) = p
sig2mock(p::Pair) = (p.first, Vararg{Any}) => p.second
sig2mock(t::Tuple) = t => Mock()
sig2mock(f) = (f, Vararg{Any}) => Mock()

# Has a given function and signature already been overdubbed for a given Context?
overdub_exists(::Type{Ctx}, ::F, sig::Tuple) where {Ctx, F} = any(methods(overdub)) do m
    Ts = unwrap_unionall(m.sig).types
    length(Ts) >= 3 && Ts[2] === Ctx && Ts[3] == F && collect(Ts[4:end]) == collect(sig)
end

# Implement `overdub` for a given Context, function, and signature.
function make_overdub(::Type{Ctx}, f::F, sig::Tuple) where {Ctx, F}
    sig_exs = Expr[]
    sig_names = []

    foreach(sig) do T
        T_uw = unwrap_unionall(T)
        name = gensym()

        if T_uw.name.name === :Vararg
            if T isa UnionAll && T.body isa UnionAll  # Vararg{T, N} where {T, N}.
                T = Vararg{Any}
            end
            if T isa UnionAll  # Vararg{T, N} where N.
                push!(sig_exs, :($name::$(T_uw.parameters[1])...))
                push!(sig_names, :($name...))
            else  # Vararg{T, N}.
                foreach(1:T.parameters[2]) do _i
                    push!(sig_exs, :($name::$(T.parameters[1])))
                    push!(sig_names, name)
                    name = gensym()
                end
            end
        else
            push!(sig_exs, :($name::$T))
            push!(sig_names, name)
        end
    end

    @eval Contexts Cassette.overdub(ctx::$Ctx, f::$F, $(sig_exs...)) =
        ctx.metadata[($f, $(sig...))]($(sig_names...))
end

end
