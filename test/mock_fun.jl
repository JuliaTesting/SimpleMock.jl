@testset "mock does not overwrite methods" begin
    # https://github.com/fredrikekre/jlpkg/blob/3b1c2400932dbe13fa7c3cba92bde3842315976c/src/cli.jl#L151-L160
    o = JLOptions()
    if o.warn_overwrite == 0
        args = map(n -> n === :warn_overwrite ? 1 : getfield(o, n), fieldnames(JLOptions))
        unsafe_store!(cglobal(:jl_options, JLOptions), JLOptions(args...))
    end
    mock(identity, identity)
    out = @capture_err mock(identity, identity)
    @test isempty(out)
end

@testset "Reusing Context" begin
    f(x) = strip(uppercase(x))
    # If the method checks aren't working properly, this will throw.
    @test mock(_g -> f(" hi "), strip => identity) == " HI "
    @test mock(_g -> f(" hi "), uppercase => identity) == "hi"
end

@testset "Basics" begin
    mock(identity) do id
        identity(10)
        @test called_once_with(id, 10)
    end

    mock(identity) do id
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
    mock((+, Float64, Int) => Mock(; side_effect=(a, b) -> 2a + b)) do plus
        @test 1 + 1 == 2
        @test 2.0 + 1 == 5.0
        @test called_once_with(plus, 2.0, 1)
    end
end

@testset "Varargs" begin
    varargs(::Int, ::Int, ::String, ::String, ::String, ::Bool...) = true
    varargs(args...) = false

    mock((varargs, Vararg{Int, 2}, Vararg{String, 3}, Vararg{Bool})) do va
        @test varargs(0, 0, "", "", "") !== true
        @test varargs(0, 0, "", "", "", false, false) !== true
        @test !varargs()
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

@testset "Filters" begin
    @testset "Maximum/minimum depth" begin
        f(x) = identity(x)
        g(x) = f(x)
        h(x) = g(x)

        mock(identity; filters=[max_depth(3)]) do id
            @test f(1) != 1
            @test g(2) != 2
            @test h(3) == 3
            @test ncalls(id) == 2 && has_calls(id, Call(1), Call(2))
        end

        mock(identity; filters=[min_depth(3)]) do id
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

        mock(identity; filters=[excluding(Bar, c)]) do id
            @test Bar.a(1) == 1
            @test Bar.b(2) == 2
            @test c(3) == 3
            @test d(4) != 4
        end

        mock(identity; filters=[including(Bar, c)]) do id
            @test Bar.a(1) != 1
            @test Bar.b(2) != 2
            @test c(3) != 3
            @test d(4) == 4
        end
    end
end
