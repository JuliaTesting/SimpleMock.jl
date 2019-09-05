module SimpleMock

using Base: Callable
using Base.Iterators: Pairs

using Cassette: Cassette

const DEFAULT = gensym()

export
    @mock,
    Cassette,
    Call,
    Mock,
    calls,
    ncalls,
    called,
    called_once,
    called_with_args,
    called_once_with_args,
    has_call,
    has_calls,
    reset!

"""
    @mock fn begin #= ... =# end

Mock the function `fn` inside of a block, so that calling it returns a [`Mock`](@ref).
"""
macro mock(fn, block)
    Ctx = gensym()
    ex = quote
        @eval Cassette.@context $Ctx
        @eval Cassette.overdub(ctx::$Ctx, ::typeof($fn), args...; kwargs...) =
            ctx.metadata(args...; kwargs...)
        Cassette.@overdub $Ctx(; metadata=Mock()) $block
    end
    return esc(ex)
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

Create a new mocking object.

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
struct Mock
    id::Symbol
    calls::Vector{Call}
    vars::Dict{Symbol, Any}
    ret::Any
    effect::Any
end

Mock(; return_value=DEFAULT, side_effect=nothing) =
    Mock(gensym(), [], Dict(), return_value, side_effect)

Base.:(==)(a::Mock, b::Mock) = getfield(a, :id) === getfield(b, :id)
Base.show(io::IO, ::MIME"text/plain", m::Mock) = print(io, "Mock(id=$(getfield(m, :id)))")

"""
    (m::Mock)(args...; kwargs...)

Calling a `Mock` triggers its `side_effect` or `return_value`.
If neither are configured, a brand new `Mock` is returned.

Either way, the call is recorded in the original `Mock`'s history.
"""
function (m::Mock)(args...; kwargs...)
    c = Call(args, kwargs)
    push!(getfield(m, :calls), c)

    effect = getfield(m, :effect)
    effect isa Vector && (effect = popfirst!(effect))
    effect isa Exception && throw(effect)
    effect isa Callable && effect(args...; kwargs...)  # TODO: Arbitrary callable types.
    effect === nothing || return effect

    ret = getfield(m, :ret)
    return ret === DEFAULT ? Mock() : ret
end

Base.getproperty(m::Mock, s::Symbol) = get!(Mock, getfield(m, :vars), s)

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
    called_with_args(::Mock, args...; kwargs...) -> Bool

Return whether or not the [`Mock`](@ref) has been called with the given arguments.
"""
called_with_args(m::Mock, args...; kwargs...) = has_call(m, Call(args, kwargs))

"""
    called(::Mock) -> Bool

Return whether or not the [`Mock`](@ref) has been called exactly once with the given arguments.
"""
called_once_with_args(m::Mock, args...; kwargs...) =
    called_once(m) && called_with_args(m, args...; kwargs...)

"""
    reset!(::Mock)

Reset a [`Mock`](@ref)'s call history and internal variables.
Side effects and return values are preserved.
"""
reset!(m::Mock) = (empty!(m.calls); empty!(m.vars))

"""
    has_call(::Mock, ::Call) -> Bool

Similiar to [`called_with_args`](@ref), but using a [`Call`](@ref).
"""
has_call(m::Mock, c::Call) = c in calls(m)

"""
    has_calls(::Mock, ::Calls...) -> Bool

Return whether or not the [`Mock`](@ref) has a particular ordered sequence of [`Call`](@ref)s.
"""
function has_calls(m::Mock, cs::Call...)
    # TODO: Does not work.
    # Is this the best way to do it? Basically slide a window across the call list.
    existing = calls(m)
    isempty(cs) && return true
    length(cs) > ncalls(m) && return false
    cs = collect(cs)
    n = length(cs) - 1
    for i in 1:(ncalls(m) - n)
        existing[i:i+n] == cs && return true
    end
    return false
end

end
