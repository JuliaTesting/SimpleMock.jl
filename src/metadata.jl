module Skipped end

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
@static if VERSION >= v"1.4"
    current_depth(m::Metadata) = length(m.mods) - count(m -> m === Skipped, m.mods) - 1
else
    current_depth(m::Metadata) = length(m.mods) - 1
end

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
@static if VERSION >= v"1.4"
    function current_function(m::Metadata)
        i = length(m.funcs) - 1
        while m.funcs[i] === Skipped
            i -= 1
        end
        return m.funcs[i]
    end
else
    current_function(m::Metadata) = m.funcs[end-1]
end

"""
    current_module(m::Metadata) -> Module

Return the current module, where "current" has the same definition as in [`current_function`](@ref).
"""
@static if VERSION >= v"1.4"
    function current_module(m::Metadata)
        i = length(m.mods) - 1
        while m.mods[i] === Skipped
            i -= 1
        end
        return m.mods[i]
    end
else
    current_module(m::Metadata) = m.mods[end-1]
end

# Ensure that the current state satisfies all filters.n
should_mock(m::Metadata{false}, method::Tuple) = method in m.methods
should_mock(m::Metadata, method::Tuple) = method in m.methods && all(f -> f(m), m.filters)

# Update the function/module stacks.
function update!(m::Metadata, ::typeof(prehook), @nospecialize(f), @nospecialize(args...))
    f_uw = unwrap_fun(f)
    @static if VERSION >= v"1.4"
        # I have no idea what is really going on under the hood here...
        # But try to avoid some weird duplicate call recording.
        fname = string(typeof(f_uw).name.name)
        upper = m.funcs[end]
        if match(Regex("#$upper#\\d+"), fname) !== nothing
            push!(m.funcs, Skipped)
            push!(m.mods, Skipped)
            return
        end
    end

    Ts = Tuple{map(typeof, args)...}
    mod = if f_uw isa Builtin || !hasmethod(f_uw, Ts)
        parentmodule(f_uw)
    else
        parentmodule(f_uw, Ts)
    end

    push!(m.funcs, f_uw)
    push!(m.mods, mod)
end

function update!(m::Metadata, ::typeof(posthook), @nospecialize(args...))
    pop!(m.funcs)
    pop!(m.mods)
end

# If a function is a keyword wrapper, try to get the wrapped function.
# This garbage is the result of random experimentation and is very sketchy.
# It fails in the case of closures.
unwrap_fun(f) = f
unwrap_fun(f::Builtin) = f
function unwrap_fun(f::F) where F <: Function
    fname = string(F.name.name)
    if VERSION >= v"1.4"
        # #FNAME##kw
        endswith(fname, "##kw") || return f
        name = Symbol(fname[2:end-4])
    else
        # #kw##FNAME
        startswith(fname, "#kw##") || return f
        name = Symbol(fname[6:end])
    end

    name_hash = Symbol("#", name)
    mod = F.name.module

    return if isdefined(mod, name)
        getfield(mod, name)
    elseif isdefined(mod, name_hash)
        gf = getfield(mod, name_hash)
        isdefined(gf, :instance) ? gf.instance : f
    else
        f
    end
end
