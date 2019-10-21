@testset "Basics" begin
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
    @test ncalls(m) == 10
    reset!(m)
    @test !called(m)
end

@testset "Effects" begin
    m = Mock()
    @test m() isa Mock
    @test m(1; x=1) isa Mock
    @test m() != m()

    m = Mock(1)
    @test m() == 1
    @test m(1; x=1) == 1

    m = Mock([1, 2, 3])
    @test m() == 1
    @test m() == 2
    @test m() == 3
    @test_throws ArgumentError m()

    m = Mock(iseven)
    @test !m(1)
    @test m(2)

    m = Mock(KeyError(1))
    @test_throws KeyError m()

    m = Mock([KeyError(1), ArgumentError("foo")])
    @test_throws KeyError m()
    @test_throws ArgumentError m()

    m = Mock([KeyError(1), [], 1, ArgumentError("foo")])
    @test_throws KeyError m()
    @test m() == []
    @test m() == 1
    @test_throws ArgumentError m()

    @eval begin
        struct Foo end
        (::Foo)(x) = x
    end
    m = Mock(Foo())
    @test m(1) == 1
    @test_throws MethodError m(1, 2)
end

@testset "Show methods" begin
    mime = MIME("text/plain")

    @test sprint(show, mime, Call(1, 2, 3)) == "Call(1, 2, 3)"
    @test sprint(show, mime, Call('a')) == "Call('a')"
    @test sprint(show, mime, Call(; x=1, y='a')) == "Call(; x=1, y='a')"

    m = Mock()
    @test sprint(show, mime, m) == "Mock(id=$(m.id))"
end

@testset "Equality" begin
    @test Call() == Call()
    @test Call(1) != Call(2)
    @test Call(1) != Call()
    @test Call(; x=1) == Call(; x=1)
    @test Call(; x=1) != Call(; x=2)

    @test Mock() != Mock()
    @test Mock(1) != Mock(1)
end
