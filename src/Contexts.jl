module Contexts

using Core: Builtin, IntrinsicFunction

using Cassette: Cassette, posthook, prehook, @context

mutable struct Metadata
    mocks::Dict{<:Tuple, <:Any}
    depth::Int
    mods::Vector{Module}
    funcs::Vector{Any}

    Metadata(mocks) = new(mocks, 0, [Main], [nothing])
end

# Get the current call depth.
current_depth(m::Metadata) = m.depth

# These functions indicate the function and module of the *outer* call.
# For exampel, if Foo.add calls +, then inside +:
# - current_function is Foo.add
# - current_module is Foo
current_function(m::Metadata) = m.funcs[end-1]
current_module(m::Metadata) = m.mods[end-1]

# Update the call depth and function/module stacks.
function update!(m::Metadata, ::typeof(prehook), f, args...)
    m.depth += 1
    push!(m.funcs, f)

    Ts = Tuple{map(typeof, args)...}
    if f isa Builtin || f isa IntrinsicFunction || !hasmethod(f, Ts)
        push!(m.mods, parentmodule(f))
    else
        push!(m.mods, parentmodule(f, Tuple{map(typeof, args)...}))
    end

    return m
end

function update!(m::Metadata, ::typeof(posthook), f, args...)
    m.depth -= 1
    pop!(m.funcs)
    pop!(m.mods)
    return m
end

end
