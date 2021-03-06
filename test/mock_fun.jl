const IDENTITY_VA = gensym()

@testset "Basics" begin
    mock(IDENTITY_VA, identity) do id
        identity(10)
        @test called_once_with(id, 10)
    end

    mock(IDENTITY_VA, identity) do id
        identity(1, 2, 3)
        identity()
        @test called(id)
        @test called_with(id, 1, 2, 3)
        @test !called_once(id)
        @test ncalls(id) == 2
        @test has_call(id, Call(1, 2, 3))
        @test has_calls(id, Call(1, 2, 3), Call())
    end
end

@testset "Non-Mock mocks" begin
    @test mock(_id -> identity(2) == 4, identity => x -> 2x)
end

@testset "Specific methods" begin
    mock((+, Float64, Int) => Mock((a, b) -> 2a + b)) do plus
        @test 1 + 1 == 2
        @test 2.0 + 1 == 5.0
        @test called_once_with(plus, 2.0, 1)
    end
end

@testset "Multiple mocks" begin
    mock(*, /) do mul, div
        @test 1 * 1 != 1
        @test 1 / 1 != 1
        @test called_once_with(mul, 1, 1)
        @test called_once_with(div, 1, 1)
    end
end

@testset "Varargs" begin
    varargs(::Int, ::Int, ::String, ::String, ::String, ::Bool...) = true
    varargs(::Any) = false

    mock((varargs, Vararg{Int, 2}, Vararg{String, 3}, Vararg{Bool})) do va
        @test varargs(0, 0, "", "", "") !== true
        @test varargs(0, 0, "", "", "", false, false) !== true
        @test !varargs(0)
        @test ncalls(va) == 2
        @test has_calls(va, Call(0, 0, "", "", ""), Call(0, 0, "", "", "", false, false))
    end
end

@testset "Parametric types" begin
    params(::Vector{Int}) = 1
    params(::Vector{Bool}) = 2
    params(::Vector{<:AbstractString}) = 3
    params(::Vector{T}) where T <: Number = 4

    mock((params, Vector{Int})) do p
        @test params([1]) != 1
        @test params([true]) == 2
        @test called_once_with(p, [1])
    end

    mock((params, Vector{<:AbstractString})) do p
        @test params([""]) != 3
        @test params([strip("")]) != 3
        @test params([1.0]) == 4
        @test ncalls(p) == 2
        @test has_calls(p, Call([""]), Call([strip("")]))
    end

    mock((params, Vector{<:Number})) do p
        @test params([""]) == 3
        @test params([1.0]) != 4
        @test called_once_with(p, [1.0])
    end
end

@testset "mock does not overwrite methods" begin
    # https://github.com/fredrikekre/jlpkg/blob/3b1c2400932dbe13fa7c3cba92bde3842315976c/src/cli.jl#L151-L160
    o = JLOptions()
    if o.warn_overwrite == 0
        args = map(n -> n === :warn_overwrite ? 1 : getfield(o, n), fieldnames(JLOptions))
        unsafe_store!(cglobal(:jl_options, JLOptions), JLOptions(args...))
    end
    ctx = gensym()
    mock(identity, ctx, identity)
    out = @capture_err mock(identity, ctx, identity)
    @test isempty(out)
end

@testset "Reusing Context" begin
    f(x) = strip(uppercase(x))
    # If the method checks aren't working properly, this will throw.
    ctx = gensym()
    @test mock(_f -> f(" hi "), ctx, strip => identity) == " HI "
    @test mock(_f -> f(" hi "), ctx, uppercase => identity) == "hi"
end

@testset "Any context name is valid" begin
    # This will throw if the context names aren't independent of the user-supplied names.
    @test mock(_id -> true, :mock, identity)
end

@testset "Filters" begin
    @testset "Maximum/minimum depth" begin
        f(x) = identity(x)
        g(x) = f(x)
        h(x) = g(x)

        mock(IDENTITY_VA, identity; filters=[max_depth(3)]) do id
            @test f(1) != 1
            @test g(2) != 2
            @test h(3) == 3
            @test ncalls(id) == 2 && has_calls(id, Call(1), Call(2))
        end

        mock(IDENTITY_VA, identity; filters=[min_depth(3)]) do id
            @test f(1) == 1
            @test g(2) != 2
            @test h(3) != 3
            @test ncalls(id) == 2 && has_calls(id, Call(2), Call(3))
        end
    end

    @testset "Exclude/include" begin
        @eval module Bar
        a(x) = identity(x)
        b(x) = identity(x)
        end
        c(x) = identity(x)
        d(x) = identity(x)

        mock(IDENTITY_VA, identity; filters=[excluding(Bar, c)]) do id
            @test Bar.a(1) == 1
            @test Bar.b(2) == 2
            @test c(3) == 3
            @test d(4) != 4
        end

        mock(IDENTITY_VA, identity; filters=[including(Bar, c)]) do id
            @test Bar.a(1) != 1
            @test Bar.b(2) != 2
            @test c(3) != 3
            @test d(4) == 4
        end
    end
end

@testset "Keyword arguments" begin
    foo(; kwargs...) = get(kwargs, :foo, nothing)
    bar(; kwargs...) = foo(; kwargs...)
    baz(; kwargs...) = bar(; kwargs...)

    @testset "Keyword arguments are passed to mocked functions" begin
        mock(foo) do f
            @test bar(; foo=:bar) !== :bar
            @test called_once_with(f; foo=:bar)
        end
    end

    @testset "Keyword arguments are discarded when recursing" begin
        ctx = gensym()

        mock(ctx, bar; filters=[including()]) do _b
            @test_logs (:warn, "Discarding keyword arguments") baz(; foo=:baz)
            @test @suppress baz(; foo=:baz) === nothing
        end

        mock(ctx, foo) do f
            @test_logs (:warn, "Discarding keyword arguments") baz(; foo=:baz)
            result = @suppress baz(; foo=:baz)
            @test result !== nothing && result !== :baz
            @test ncalls(f) == 2 && has_calls(f, Call(), Call())
        end
    end

    @testset "Metadata records original functions and not keyword wrappers" begin
        @eval begin
            kw_f(; x) = kw_g(; x=x)
            kw_g(; x) = 2x
            kw_h = (; x) -> kw_i(; x=x)
            kw_i = (; x) -> 2x
        end
        kw_j(; x) = kw_k(; x=x)
        kw_k(; x) = 2x

        test(f; broken::Bool=false) = function(m::SimpleMock.Metadata)
            eq = SimpleMock.current_function(m) === f
            if broken
                @test_broken eq
            else
                @test eq
            end
            return true
        end

        # Regular functions.
        @test mock(_g -> kw_f(; x=1), kw_g; filters=[test(kw_f)]) != 2
        # Anonymous functions.
        @test mock(_i -> kw_h(; x=1), kw_i; filters=[test(kw_h)]) != 2
        # Closures.
        @test mock(_k -> kw_j(; x=1), kw_k; filters=[test(kw_j; broken=true)]) != 2
    end
end
