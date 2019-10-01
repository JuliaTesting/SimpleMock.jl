@context MockCtx

# TODO: Maybe these should be inlined, but it slows down compilation a lot.

@noinline function Cassette.prehook(ctx::MockCtx{Metadata{true}}, f, args...)
    @nospecialize f args
    update!(ctx.metadata, prehook, f, args...)
end

@noinline function Cassette.posthook(ctx::MockCtx{Metadata{true}}, v, f, args...)
    @nospecialize v f args
    update!(ctx.metadata, posthook, f, args...)
end

"""
    mock(f::Function, args...; filters::Vector{<:Function}=Function[])

Run `f` with specified functions mocked out.

!!! note
    Keyword arguments to mocked functions are not supported.
    If you call a mocked function with keyword arguments, it will dispatch to the original function.
    For more details, see [Cassette#48](https://github.com/jrevels/Cassette.jl/issues/48).

## Examples

Mocking a single function:

```julia
f(x) = x + 1
mock(+) do plus
    @assert plus isa Mock
    @assert f(0) != 1  # The call to + is mocked.
    @assert called_once_with(p, 0, 1)
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

## Using Filters

Oftentimes, you mock a function with a very specific idea of where you want that mocking to happen.
It can be confusing when a call you didn't anticipate gets mocked somewhere deep in the call stack, botching everything.
To avoid this, you can use filter functions like so:

```julia
f(x, y) = x + y
g(x, y) = f(x, y)
mock((+) => Mock(; side_effect=(a, b) -> 2a + 2b); filters=[max_depth(2)]) do plus
    @assert f(1, 2) == 6  # The call depth of print here is 2.
    @assert g(3, 4) == 7  # Here, it's 3.
    @assert called_once_with(plus, 1, 2)
end
```

Filter functions take a single argument of type [`Metadata`](@ref).
If any filter rejects, then mocking is not performed.
See [Filter Functions](@ref) for a list of included filters, as well as building blocks for you to create your own.
"""
function mock(f::Function, args...; filters::Vector{<:Function}=Function[])
    mocks = map(sig2mock, args)  # ((f, sig) => mock).
    isempty(mocks) && throw(ArgumentError("At least one function must be mocked"))

    # Implement the overdub, but only if it's not already implemented.
    has_new_overdub = any(map(first, mocks)) do k
        fun = k[1]
        sig = k[2:end]
        if overdub_exists(fun, sig)
            false
        else
            make_overdub(fun, sig)
            true
        end
    end

    # Only use `invokelatest` if the Context/overdub implementations are new.
    od_args = [MockCtx(; metadata=Metadata(Dict(mocks), filters)), f, map(last, mocks)...]
    return has_new_overdub ? invokelatest(overdub, od_args...) : overdub(od_args...)
end

# Output (f, sig) => mock.
sig2mock(p::Pair{<:Tuple}) = p
sig2mock(p::Pair) = (p.first, Vararg{Any}) => p.second
sig2mock(t::Tuple) = t => Mock()
sig2mock(f) = (f, Vararg{Any}) => Mock()

# Has a given function and signature already been overdubbed?
overdub_exists(::F, sig::Tuple) where F = any(methods(overdub)) do m
    squashed = reduce(sig; init=[]) do acc, T
        if T isa DataType && T.name.name === :Vararg
            append!(acc, repeat([T.parameters[1]], T.parameters[2]))
        else
            push!(acc, T)
        end
    end
    m.sig === Tuple{typeof(overdub), MockCtx, F, squashed...}
end

# Implement `overdub` for a given Context, function, and signature.
function make_overdub(f::F, sig::Tuple) where F
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

    @eval @inline function Cassette.overdub(ctx::MockCtx, f::$F, $(sig_exs...))
        method = (f, $(sig...))
        if should_mock(ctx.metadata, method)
            ctx.metadata.mocks[method]($(sig_names...))
        else
            recurse(ctx, f, $(sig_names...))
        end
    end
end
