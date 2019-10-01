const SYMBOL = Ref(:_)

"""
    mock(f::Function[, ctx::Symbol], args...; filters::Vector{<:Function}=Function[])

Run `f` with specified functions mocked out.

!!! note
    Keyword arguments to mocked functions are not supported.
    If you call a mocked function with keyword arguments, it will dispatch to the original function.
    For more details, see [Cassette#48](https://github.com/jrevels/Cassette.jl/issues/48).

## Examples

Mocking a single function:

```julia
mock(print) do p
    @assert p isa Mock
    println("!")  # This won't output anything.
    @assert called_once_with(p, stdout, "!", '\\n')
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
f(x) = print(x)
g(x) = f(x)
mock(print; filters=[max_depth(2)]) do p
    f("this won't print")  # The call depth of print here is 2.
    g("this will print")   # Here, it's 3.
    @assert called_once_with(p, "this won't print")
end
```

Filter functions take a single argument of type [`Metadata`](@ref).
If any filter rejects, then mocking is not performed.
See [Filter Functions](@ref) for a list of included filters, as well as building blocks for you to create your own.

## Performance Tips

### Avoid Printing

Printing is, for whatever reason, glacially slow inside of mock blocks.
To illustrate:

```julia
julia> @time mock(println, log)
Mock{Symbol,Nothing}(Symbol("##390"), Call[], Symbol("##371"), nothing)
  7.389156 seconds (19.52 M allocations: 1.029 GiB, 7.71% gc time)

julia> @time println(mock(identity, log))
Mock{Symbol,Nothing}(Symbol("##394"), Call[], Symbol("##371"), nothing)
  0.136950 seconds (120.96 k allocations: 6.507 MiB
```

This includes the display of failed `@test`s,  so it's wise to avoid making test assertions in the mocked environment.

```julia
#= bad:  =# mock(lg -> @test(!called(lg), log)
#= good: =# @test !called(mock(identity, log))
```

The second strategy is orders of magnitude faster than the first when the test fails, and it's also faster when the test passes.

### Don't Filter Unless Necessary

Filtering introduces significant bookkeeping overhead.
Avoid it whenever possible!

### Reuse Your `Context`s

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
"""
function mock end

function mock(f::Function, args...; filters::Vector{<:Function}=Function[])
    name = SYMBOL[] = Symbol(SYMBOL[], :A)
    return mock(f, name, args...; filters=filters)
end

function mock(f::Function, ctx::Symbol, args...; filters::Vector{<:Function}=Function[])
    mocks = map(sig2mock, args)  # ((f, sig) => mock).

    # Create the Context type if it doesn't already exist.
    ctx_is_new, Ctx = if isdefined(Contexts, ctx)
        false, getfield(Contexts, ctx)
    else
        true, @eval Contexts @context $ctx
    end

    # Implement the tracking hooks necessary for filtering.
    if ctx_is_new
        @eval Contexts begin
            @noinline function Cassette.prehook(ctx::$Ctx, f, args...)
                @nospecialize f args
                update!(ctx.metadata, prehook, f, args...)
            end
            @noinline function Cassette.posthook(ctx::$Ctx, v, f, args...)
                @nospecialize v f args
                update!(ctx.metadata, posthook, f, args...)
            end
        end
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
    meta = Metadata(Dict(mocks), filters)
    c = ctx_is_new ? invokelatest(Ctx; metadata=meta) : Ctx(; metadata=meta)
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

    @eval Contexts function Cassette.overdub(ctx::$Ctx, f::$F, $(sig_exs...))
        method = (f, $(sig...))
        if should_mock(ctx.metadata, method)
            ctx.metadata.mocks[method]($(sig_names...))
        else
            recurse(ctx, f, $(sig_names...))
        end
    end
end
