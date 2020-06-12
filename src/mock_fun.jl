const KW_WRAPPERS = Set{DataType}()

@context Ctx

struct Meta{Fs}
    mocks::IdDict{DataType, Any}

    function Meta(mocks)
        Fs = Union{map(p -> typeof(first(p)), mocks)...}
        dict = IdDict(typeof(p.first) => p.second for p in mocks)
        return new{Fs}(dict)
    end
end

@inline Cassette.overdub(ctx::Ctx{Meta{Fs}}, ::F, args...; kwargs...) where {Fs, F <: Fs} =
    ctx.metadata.mocks[F](args...; kwargs...)

fun2mock(p::Pair) = p
fun2mock(f) = f => Mock()

has_kws(f::Callable) = isdefined(methods(f).mt, :kwsorter)
has_kws(f) = @static VERSION < v"1.4" ? true : any(m -> !isempty(kwarg_decl(m)), methods(f))

kw_wrapper_exists(::F) where F = F in KW_WRAPPERS

should_make_kw_wrapper(f) = has_kws(f) && !kw_wrapper_exists(f)

function make_kw_wrapper(::F) where F
    push!(KW_WRAPPERS, F)
    @eval @inline function Cassette.overdub(
        ctx::Ctx{Meta{Fs}}, ::kwftype($F), kwargs, f::$F, args...,
    ) where Fs >: $F
        return overdub(ctx, f, args...; kwargs...)
    end
end

"""
    mock(f, args...)

Run `f` with specified functions mocked out.

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

Mocking with something other than a `Mock`:

```julia
mock((+) => (a, b) -> 2a + 2b) do _plus
    @assert 1 + 2 == 6
end
```
"""
function mock(f, args...)
    mocks = map(fun2mock, args)
    new_methods = false
    foreach(map(first, mocks)) do fun
        if should_make_kw_wrapper(fun)
            make_kw_wrapper(fun)
            new_methods = true
        end
    end
    ctx = Ctx(; metadata=Meta(mocks))
    od_args = [ctx, f, map(last, mocks)...]
    return new_methods ? invokelatest(overdub, od_args...) : overdub(od_args...)
end
