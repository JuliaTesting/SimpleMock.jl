"""
Container for mocks and bookkeeping data.
Instances of this type are aware of the call depth ([`current_depth`](@ref)) and the current function/module ([`current_function`](@ref)/[`current_module`](@ref)).

All filter functions take a single argument of this type.
"""
struct Metadata{B}
    mocks::Dict{<:Tuple, <:Any}
    methods::Set{<:Tuple}
    filters::Vector{<:Function}
    mods::Vector{Module}
    funcs::Vector{Any}

    Metadata(mocks::Dict{<:Tuple}, filters::Vector{<:Function}) =
        new{!isempty(filters)}(mocks, Set(keys(mocks)), filters, [Main], [nothing])
end

"""
    current_depth(::Metadata) -> Int

Return the current call depth (the size of the call stack).
The depth is always positive, so the first function entered has a depth of 1.
"""
current_depth(m::Metadata) = length(m.funcs) - 1

"""
    current_function(::Metadata) -> Any

Return the current function (or other callable thing).
In this case, "current" refers, somewhat counterintuitively, not to the function about to be called, but to the function that is about to call it.

To illustrate:

```julia
f(x) = x
g(x) = f(x)
x = g(1)
```

In this case, when the call to `f` is reached, the function that is calling `f` is `g`.
Therefore, the "current" function is `g`.
"""
current_function(m::Metadata) = m.funcs[end-1]

"""
    current_module(m::Metadata) -> Module

Return the current module, where "current" has the same definition as in [`current_function`](@ref).
"""
current_module(m::Metadata) = m.mods[end-1]

# Ensure that the current state satisfies all filters.n
should_mock(m::Metadata{false}, method::Tuple) = method in m.methods
should_mock(m::Metadata, method::Tuple) = method in m.methods && all(f -> f(m), m.filters)

# Update the function/module stacks.
function update!(m::Metadata, ::typeof(prehook), @nospecialize(f), @nospecialize(args...))
    Ts = Tuple{map(typeof, args)...}
    mod = if f isa Union{Builtin, IntrinsicFunction} || !hasmethod(f, Ts)
        parentmodule(f)
    else
        parentmodule(f, Ts)
    end
    push!(m.funcs, f)
    push!(m.mods, mod)
end

function update!(m::Metadata, ::typeof(posthook), @nospecialize(args...))
    pop!(m.funcs)
    pop!(m.mods)
end
