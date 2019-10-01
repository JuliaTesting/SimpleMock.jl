const IDENTITY_VA = gensym()

@testset "Basics" begin
    result = mock(IDENTITY_VA, identity) do id
        identity(10)
        called_once_with(id, 10)
    end
    @test result

    result = mock(IDENTITY_VA, identity) do id
        identity(1, 2, 3)
        identity()
        [
            called(id),
            called_with(id, 1, 2, 3),
            !called_once(id),
            ncalls(id) == 2,
            has_call(id, Call(1, 2, 3)),
            has_calls(id, Call(1, 2, 3), Call()),
        ]
    end
    @test all(result)
end

@testset "Non-Mock mocks" begin
    @test mock(_id -> identity(2) == 4, IDENTITY_VA, identity => x -> 2x)
end

@testset "Specific methods" begin
    result = mock((+, Float64, Int) => Mock(; side_effect=(a, b) -> 2a + b)) do plus
        [
            1 + 1 == 2,
            2.0 + 1 == 5.0,
            called_once_with(plus, 2.0, 1),
        ]
    end
    @test all(result)
end

@testset "Varargs" begin
    varargs(::Int, ::Int, ::String, ::String, ::String, ::Bool...) = true
    varargs(args...) = false

    result = mock((varargs, Vararg{Int, 2}, Vararg{String, 3}, Vararg{Bool})) do va
        [
            varargs(0, 0, "", "", "") !== true,
            varargs(0, 0, "", "", "", false, false) !== true,
            !varargs(),
            ncalls(va) == 2,
            has_calls(va, Call(0, 0, "", "", ""), Call(0, 0, "", "", "", false, false)),
        ]
    end
    @test all(result)
end

@testset "Parametric types" begin
    params(::Vector{Int}) = 1
    params(::Vector{Bool}) = 2
    params(::Vector{<:AbstractString}) = 3
    params(::Vector{T}) where T <: Number = 4

    result = mock((params, Vector{Int})) do p
        [
            params([1]) != 1,
            params([true]) == 2,
            called_once_with(p, [1]),
        ]
    end
    @test all(result)

    mock((params, Vector{<:AbstractString})) do p
        [
            params([""]) != 3,
            params([strip("")]) != 3,
            params([1.0]) == 4,
            ncalls(p) == 2,
            has_calls(p, Call([""]), Call([strip("")])),
        ]
    end
    @test all(result)

    result = mock((params, Vector{<:Number})) do p
        [
            params([""]) == 3,
            params([1.0]) != 4,
            called_once_with(p, [1.0]),
        ]
    end
    @test all(result)
end

@testset "mock does not overwrite methods" begin
    # https://github.com/fredrikekre/jlpkg/blob/3b1c2400932dbe13fa7c3cba92bde3842315976c/src/cli.jl#L151-L160
    o = JLOptions()
    if o.warn_overwrite == 0
        args = map(n -> n === :warn_overwrite ? 1 : getfield(o, n), fieldnames(JLOptions))
        unsafe_store!(cglobal(:jl_options, JLOptions), JLOptions(args...))
    end
    Ctx = gensym()
    mock(identity, Ctx, identity)
    out = @capture_err mock(identity, Ctx, identity)
    @test isempty(out)
end

@testset "Filters" begin
    @testset "Maximum/minimum depth" begin
        f(x) = identity(x)
        g(x) = f(x)
        h(x) = g(x)

        result = mock(IDENTITY_VA, identity; filters=[max_depth(3)]) do id
            [
                f(1) != 1,
                g(2) != 2,
                h(3) == 3,
                ncalls(id) == 2 && has_calls(id, Call(1), Call(2)),
            ]
        end
        @test all(result)

        result = mock(IDENTITY_VA, identity; filters=[min_depth(3)]) do id
            [
                f(1) == 1,
                g(2) != 2,
                h(3) != 3,
                ncalls(id) == 2 && has_calls(id, Call(2), Call(3)),
            ]
        end
        @test all(result)
    end

    @testset "Exclude/include" begin
        @eval module Bar
        a(x) = identity(x)
        b(x) = identity(x)
        end
        c(x) = identity(x)
        d(x) = identity(x)

        result = mock(IDENTITY_VA, identity; filters=[excluding(Bar, c)]) do id
            [
                Bar.a(1) == 1,
                Bar.b(2) == 2,
                c(3) == 3,
                d(4) != 4,
            ]
        end
        @test all(result)

        result = mock(IDENTITY_VA, identity; filters=[including(Bar, c)]) do id
            [
                Bar.a(1) != 1,
                Bar.b(2) != 2,
                c(3) != 3,
                d(4) == 4,
            ]
        end
        @test all(result)
    end
end

@testset "Reusing Context" begin
    f(x) = strip(uppercase(x))
    ctx = gensym()
    # If the method checks aren't working properly, this will throw.
    @test mock(_g -> f(" hi "), ctx, strip => identity) == " HI "
    @test mock(_g -> f(" hi "), ctx, uppercase => identity) == "hi"
end
