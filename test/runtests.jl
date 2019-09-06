using SimpleMock
using Test

@testset "SimpleMock.jl" begin
    @testset "Basic Mock behaviour" begin
        m = Mock()
        @test isempty(calls(m))
        @test ncalls(m) == 0
        @test !called(m)
        @test !called_once(m)
        @test !called_with(m)
        @test !called_once_with(m)

        m()
        @test length((calls(m))) == 1
        @test ncalls(m) == 1
        @test called(m)
        @test called_once(m)
        @test called_with(m)
        @test called_once_with(m)

        m(1)
        @test !called_once(m)
        @test called_with(m, 1)
        @test !called_once_with(m, 1)

        m(1; x=2)
        @test called_with(m, 1; x=2)
    end

    @testset "has_calls" begin
        m = Mock()
        @test has_calls(m)
        @test !has_calls(m, Call())

        m()
        @test has_calls(m, Call())
        @test !has_calls(m, Call(1))
        @test !has_calls(m, Call(; x=1))
        @test !has_calls(m, Call(), Call())

        m(1)
        @test has_calls(m, Call(), Call(1))

        m(2)
        m(3)
        m(4)
        @test has_calls(m, Call(2), Call(3))
        @test !has_calls(m, Call(2), Call(4))

        m(; x=1)
        @test has_calls(m, Call(4), Call(; x=1))
    end

    @testset "reset!" begin
        m = Mock()
        foreach(m, 1:10)
        reset!(m)
        @test !called(m)
    end

    @testset "Return values" begin
        m = Mock()
        @test m() isa Mock
        @test m(1; x=1) isa Mock

        m = Mock(; return_value=1)
        @test m() == 1
        @test m(1; x=1) == 1
    end

    @testset "Side effects" begin
        m = Mock(; side_effect=1)
        @test m() == 1
        @test m(1, x=1) == 1

        m = Mock(; side_effect=[1, 2, 3])
        @test m() == 1
        @test m() == 2
        @test m() == 3
        @test_throws ArgumentError m()

        m = Mock(; side_effect=KeyError(1))
        @test_throws KeyError m()

        m = Mock(; side_effect=[KeyError(1), ArgumentError("foo")])
        @test_throws KeyError m()
        @test_throws ArgumentError m()

        m = Mock(; side_effect=[KeyError(1), 1, ArgumentError("foo")])
        @test_throws KeyError m()
        @test m() == 1
        @test_throws ArgumentError m()

        m = Mock(; return_value=1, side_effect=2)
        @test m() == 2
    end

    @testset "mock" begin
        mock(get) do get
            Base.get()
            @test called_once_with(get)
        end
    end
end
