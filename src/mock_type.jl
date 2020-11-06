"""
    Call(args...; kwargs...)

Represents a function call.
"""
struct Call{T<:Tuple, P<:Pairs}
    args::T
    kwargs::P

    Call(args...; kwargs...) = new{typeof(args), typeof(kwargs)}(args, kwargs)
end

"""
    Predicate(f)

A predicate that can be used instead of literal call arguments,
useful for situations where the exact value of arguments is not known.
The function `f` is called with the observed argument, and must return a `Bool`.

## Example

```julia
m = Mock()
m(rand(1:10))
@assert called_with(m, Predicate(in(1:10)))
```
"""
struct Predicate{F}
    f::F
end

Base.show(io::IO, ::MIME"text/plain", p::Predicate) = print(io, "Predicate(", p.f, ")")

(p::Predicate)(x) = p.f(x)

Base.:(==)(a::Call{T1, P1}, b::Call{T2, P2}) where {T1, P1, T2, P2} = false
Base.:(==)(a::Call{T, P}, b::Call{T, P}) where {T, P} =
    a.args == b.args && a.kwargs == b.kwargs

function Base.show(io::IO, ::MIME"text/plain", c::Call)
    print(io, "Call(")
    print(io, join(map(repr, c.args), ", "))
    isempty(c.kwargs) ||
        print(io, "; ", join(map(((k, v),) -> "$k=$(repr(v))", collect(c.kwargs)), ", "))
    print(io, ")")
end

"""
    Mock([effect])

Create a new mocking object that can act as a replacement for a function.

## Effects

Use the `effect` argument to determine what happens upon calling the mock.

- If the value is callable, then it is called with the same arguments and keywords.
- If the value is an `Exception`, then the exception is thrown.
- If the value is a `Vector`, then each call consumes the next element.
  Nested `Vector`s are returned, but callables and exceptions are treated as explained above.
- Any other value is returned without modification.

By default, calling a `Mock` returns a new `Mock`.
"""
struct Mock{T}
    id::Symbol
    calls::Vector{Call}
    effect::T
end

Mock(effect=(_args...; _kwargs...) -> Mock()) = Mock(gensym(), Call[], effect)

Base.:(==)(a::Mock, b::Mock) = a.id === b.id

Base.show(io::IO, ::MIME"text/plain", m::Mock) = print(io, "Mock(id=$(m.id))")

"""
    (::Mock)(args...; kwargs...)

Calling a `Mock` records the call in its history and triggers its `effect`.
"""
function (m::Mock)(args...; kwargs...)
    push!(calls(m), Call(args...; kwargs...))
    return do_effect(m.effect, args...; kwargs...)
end

"""
    calls(::Mock) -> Vector{Call}

Return the call history of the [`Mock`](@ref).
"""
calls(m::Mock) = m.calls

"""
    last_call(::Mock) -> Call

Return the last call of the [`Mock`](@ref).
"""
last_call(m::Mock) = last(calls(m))

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
    called_last_with(::Mock, args...; kwargs...) -> Bool

Return whether or not the [`Mock`](@ref) was last called with the given arguments.
"""
called_last_with(m::Mock, args...; kwargs...) = last_call(m) == Call(args...; kwargs...)

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
has_call(m::Mock, c::Call) = any(call -> call_matches(c, call), calls(m))

"""
    has_calls(::Mock, ::Call...) -> Bool

Return whether or not the [`Mock`](@ref) has a particular ordered sequence of [`Call`](@ref)s.
"""
function has_calls(m::Mock, cs::Call...)
    isempty(cs) && return true
    existing = calls(m)
    length(cs) > length(existing) && return false
    cs = collect(cs)  # Omitting this causes a segfault?!
    n = length(cs) - 1
    for i in 1:(length(existing) - n)
        all(ab -> call_matches(ab...), zip(cs, existing[i:i+n])) && return true
    end
    return false
end

"""
    reset!(::Mock)

Reset a [`Mock`](@ref)'s call history.
Its `effect` is preserved.
"""
function reset!(m::Mock)
    empty!(m.calls)
    return m
end

# Handle the effect.
do_effect(x, args...; kwargs...) = isempty(methods(x)) ? x : x(args...; kwargs...)
do_effect(x::Callable, args...; kwargs...) = x(args...; kwargs...)
do_effect(ex::Exception, _args...; _kwargs...) = throw(ex)
function do_effect(xs::Vector, args...; kwargs...)
    x = popfirst!(xs)
    return x isa Vector ? x : do_effect(x, args...; kwargs...)
end

# Match call arguments.
call_matches(expected, observed) =
    length(expected.args) == length(observed.args) &&
    issetequal(keys(expected.kwargs), keys(observed.kwargs)) &&
    all(ab -> arg_matches(ab...), zip(expected.args, observed.args)) &&
    all(k -> arg_matches(expected.kwargs[k], observed.kwargs[k]), keys(expected.kwargs))

arg_matches(expected, observed) = expected == observed
arg_matches(pred::Predicate, observed) = pred(observed)
