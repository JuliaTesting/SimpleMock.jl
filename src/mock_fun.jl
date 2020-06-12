const CTXS = Dict{Symbol, UnionAll}()

"""
    mock(f, [ctx, ]args...)

Run `f` with specified functions mocked out.

!!! note
    Mocking functions with keyword arguments is only partially supported.
    See the "Keyword Arguments" section below for more details.

## Examples

Mocking a single function:

```julia
f(x) = x + 1
mock(+) do plus
    @assert plus isa Mock
    @assert f(0) != 1  # The call to + is mocked.
    @assert called_once_with(plus, 0, 1)
end
```

Mocking a function with a custom [`Mock`](@ref):

```julia
mock((+) => Mock(1)) do plus
    @assert 1 + 1 == 1
    @assert called_once_with(plus, 1, 1)
end
```

Mocking methods that match a given signature:

```julia
mock((+, Float64, Float64) => Mock((a, b) -> 2a + 2b)) do plus
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

## Reusing `Context`s

Under the hood, this function creates a new [Cassette `Context`](https://jrevels.github.io/Cassette.jl/stable/api.html#Cassette.Context) on every call by default.
This provides a nice clean mocking environment, but it can be slow to create and call new types and methods over and over.
If you find yourself repeatedly mocking the same set of functions, you can specify a context name to reuse that context like so:

```julia
ctx = gensym()
mock(g -> @assert(!called(g)), ctx, get)
# This one is faster, especially when there's a lot going on in your mock blocks.
mock(g -> @assert(!called(g)), ctx, get)
```

## Keyword Arguments

Mocking of functions with keyword arguments is fully supported when the context in use has no previously-mocked functions that are now unmocked.
If you reuse a context that has previously mocked some function, unmocked calls to that function will have no keywords.
For example:

```julia
kwfunc(; kwargs...) = nothing
calls_kwfunc(; kwargs...) = kwfunc(; kwargs...)
ctx = gensym()
mock(ctx, calls_kwfunc) do c
    calls_kwfunc(; x=1, y=2)
    @assert called_once_with(c; x=1, y=2)
end
mock(ctx, kwfunc) do k
    calls_kwfunc(; x=1, y=2)               # This will issue a warning.
    @assert called_once_with(k; x=1, y=2)  # This will fail!
end
```

In short, avoid reusing contexts when mocking functions that accept keywords.
"""
mock(f, args...) = mock(f, gensym(), args...)

function mock(f, ctx::Symbol, args...)
    mocks = map(sig2mock, args)  # ((f, sig) => mock).
    isempty(mocks) && throw(ArgumentError("At least one function must be mocked"))

    # Create the new context type if it doesn't already exist.
    ctx_is_new = !haskey(CTXS, ctx)
    ctx_is_new && make_context(ctx)
    Ctx = CTXS[ctx]

    # Implement the overdubs, but only if they aren't already implemented.
    has_new_od = false
    foreach(map(first, mocks)) do k
        fun = k[1]
        sig = k[2:end]
        if ctx_is_new || !overdub_exists(Ctx, fun, sig)
            make_overdub(Ctx, fun, sig)
            has_new_od = true
        end
    end

    # Only use `invokelatest` if the Context/overdub implementations are new.
    meta = Metadata(Dict(mocks))
    c = ctx_is_new ? invokelatest(Ctx; metadata=meta) : Ctx(; metadata=meta)
    od_args = [c, f, map(last, mocks)...]
    return has_new_od ? invokelatest(overdub, od_args...) : overdub(od_args...)
end

# Output (f, sig) => mock.
sig2mock(p::Pair{<:Tuple}) = p
sig2mock(p::Pair) = (p.first, Vararg{Any}) => p.second
sig2mock(t::Tuple) = t => Mock()
sig2mock(f) = (f, Vararg{Any}) => Mock()

# Create a new context type.
make_context(name) = @eval CTXS[$(QuoteNode(name))] = @context $(gensym())

# Has a given function and signature already been overdubbed?
function overdub_exists(::Type{Ctx}, ::F, sig) where {Ctx <: Context, F}
    squashed = foldl(sig; init=[]) do acc, T
        if T isa DataType && T.name.name === :Vararg
            append!(acc, repeat([T.parameters[1]], T.parameters[2]))
        else
            push!(acc, T)
        end
    end
    return any(m -> m.sig === Tuple{typeof(overdub), Ctx, F, squashed...}, methods(overdub))
end

# Implement `overdub` for a given Context, function, and signature.
function make_overdub(::Type{Ctx}, ::F, sig) where {Ctx <: Context, F}
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

    @eval begin
        @inline function Cassette.overdub(ctx::$Ctx, f::$F, $(sig_exs...); kwargs...)
            method = (f, $(sig...))
            if should_mock(ctx.metadata, method)
                ctx.metadata.mocks[method]($(sig_names...); kwargs...)
            else
                isempty(kwargs) || @warn "Discarding keyword arguments" f kwargs
                recurse(ctx, f, $(sig_names...))
            end
        end

        # https://github.com/jrevels/Cassette.jl/issues/48#issuecomment-440605481
        @inline Cassette.overdub(ctx::$Ctx, ::kwftype($F), kwargs, f::$F, $(sig_exs...)) =
            overdub(ctx, f, $(sig_names...); kwargs...)
    end
end
