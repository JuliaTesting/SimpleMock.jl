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

@testset "No mocks, multiple mocks" begin
    @test mock(() -> 1) == 1

    mock(*, /) do mul, div
        @test 1 * 1 != 1
        @test 1 / 1 != 1
        @test called_once_with(mul, 1, 1)
        @test called_once_with(div, 1, 1)
    end
end

@testset "mock does not overwrite methods" begin
    # https://github.com/fredrikekre/jlpkg/blob/3b1c2400932dbe13fa7c3cba92bde3842315976c/src/cli.jl#L151-L160
    o = JLOptions()
    if o.warn_overwrite == 0
        args = map(n -> n === :warn_overwrite ? 1 : getfield(o, n), fieldnames(JLOptions))
        unsafe_store!(cglobal(:jl_options, JLOptions), JLOptions(args...))
    end
    f(; x) = x
    mock(identity, f)
    out = @capture_err mock(identity, f)
    @test isempty(out)
end

@testset "Keyword arguments" begin
    foo(; kwargs...) = get(kwargs, :foo, nothing)
    bar(; kwargs...) = foo(; kwargs...)
    baz(; kwargs...) = bar(; kwargs...)

    mock(foo) do f
        @test bar(; foo=:bar) !== :bar
        @test called_once_with(f; foo=:bar)
    end
end
