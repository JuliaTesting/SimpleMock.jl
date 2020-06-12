struct Metadata
    mocks::Dict{<:Tuple, <:Any}
    methods::Set{<:Tuple}

    Metadata(mocks) = new(mocks, Set(keys(mocks)))
end

should_mock(m, method) = method in m.methods

# If a function is a keyword wrapper, try to get the wrapped function.
# This garbage is the result of random experimentation and is very sketchy.
# It fails in the case of closures.
unwrap_fun(f) = f
unwrap_fun(f::Builtin) = f
function unwrap_fun(f::F) where F <: Function
    fname = string(F.name.name)
    @static if VERSION >= v"1.4"
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
