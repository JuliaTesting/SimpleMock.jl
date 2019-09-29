var documenterSearchIndex = {"docs":
[{"location":"#","page":"Home","title":"Home","text":"CurrentModule = SimpleMock","category":"page"},{"location":"#SimpleMock-1","page":"Home","title":"SimpleMock","text":"","category":"section"},{"location":"#","page":"Home","title":"Home","text":"SimpleMock\nmock\nMock\ncalls\nncalls\ncalled\ncalled_once\ncalled_with\ncalled_once_with\nCall\nhas_call\nhas_calls\nreset!","category":"page"},{"location":"#SimpleMock.SimpleMock","page":"Home","title":"SimpleMock.SimpleMock","text":"A basic mocking module, inspired by Python's unittest.mock and implemented with Cassette.\n\nUsage\n\nFor usage examples, see mock.\n\nDifferences from unittest.mock\n\nSimpleMock only implements mocking of function calls, as opposed to arbitrary monkey-patching.\nNeither getfield nor setfield! is implemented for the default Mock type.\n\n\n\n\n\n","category":"module"},{"location":"#SimpleMock.mock","page":"Home","title":"SimpleMock.mock","text":"mock(f::Function[, ctx::Symbol], args...)\n\nRun f with specified functions mocked out.\n\nExamples\n\nMocking a single function:\n\nmock(print) do print\n    @assert print isa Mock\n    println(\"!\")  # This won't output anything.\n    @assert called_once_with(print, stdout, \"!\", '\\n')\nend\n\nMocking a function with a custom Mock:\n\nmock((+) => Mock(; return_value=1)) do plus\n    @assert 1 + 1 == 1\n    @assert called_once_with(plus, 1, 1)\nend\n\nMocking methods that match a given signature:\n\nmock((+, Float64, Float64) => Mock(; side_effect=(a, b) -> 2a + 2b)) do plus\n    @assert 1 + 1 == 2\n    @assert 2.0 + 2.0 == 8\n    @assert called_once_with(plus, 2.0, 2.0)\nend\n\nMocking with something other than a Mock:\n\nmock((+) => (a, b) -> 2a + 2b) do _plus\n    @assert 1 + 2 == 6\nend\n\nReusing A Context\n\nUnder the hood, this function creates a new Cassette Context on every call by default. This provides a nice clean mocking environment, but it can be slow to create and call new types and methods over and over. If you find yourself repeatedly mocking the same set of functions, you can specify a context name to reuse that context like so:\n\njulia> ctx = gensym();\n\n# The first time takes a little while.\njulia> @time mock(g -> @assert(!called(g)), ctx, get)\n  0.156221 seconds (171.93 k allocations: 9.356 MiB)\n\n# But the next time is faster!\njulia> @time mock(g -> @assert(!called(g)), ctx, get)\n  0.052324 seconds (27.38 k allocations: 1.437 MiB)\n\nBe careful though! If you call a function that you've previously mocked but are not currently mocking, you'll run into trouble:\n\njulia> f(s) = strip(uppercase(s));\njulia> ctx = gensym();\n\njulia> mock(_g -> f(\" hi \"), ctx, strip);\njulia> mock(_g -> f(\" hi \"), ctx, uppercase)\nERROR: KeyError: key (strip, Vararg{Any,N} where N) not found\n\n\n\n\n\n","category":"function"},{"location":"#SimpleMock.Mock","page":"Home","title":"SimpleMock.Mock","text":"Mock(; return_value=Mock(), side_effect=nothing)\n\nCreate a new mocking object, which behaves similarly to Python's Mock.\n\nReturn Value\n\nUse the return_value keyword to set the value to be returned upon calling the mock. By default, the return value is a new Mock.\n\nSide Effects\n\nUse the side_effect keyword to set a side effect to occur upon calling the mock.\n\nIf the value is an Exception, then the exception is thrown.\nIf the value is a function, then it is called with the same arguments and keywords.\nIf the value is a Vector, then each call uses the next element.\nAny other value is returned without modification.\n\n\n\n\n\n","category":"type"},{"location":"#SimpleMock.calls","page":"Home","title":"SimpleMock.calls","text":"calls(::Mock) -> Vector{Call}\n\nReturn the call history of the Mock.\n\n\n\n\n\n","category":"function"},{"location":"#SimpleMock.ncalls","page":"Home","title":"SimpleMock.ncalls","text":"ncalls(::Mock) -> Int\n\nReturn the number of times that the Mock has been called.\n\n\n\n\n\n","category":"function"},{"location":"#SimpleMock.called","page":"Home","title":"SimpleMock.called","text":"called(::Mock) -> Bool\n\nReturn whether or not the Mock has been called.\n\n\n\n\n\n","category":"function"},{"location":"#SimpleMock.called_once","page":"Home","title":"SimpleMock.called_once","text":"called_once(::Mock) -> Bool\n\nReturn whether or not the Mock has been called exactly once.\n\n\n\n\n\n","category":"function"},{"location":"#SimpleMock.called_with","page":"Home","title":"SimpleMock.called_with","text":"called_with(::Mock, args...; kwargs...) -> Bool\n\nReturn whether or not the Mock has been called with the given arguments.\n\n\n\n\n\n","category":"function"},{"location":"#SimpleMock.called_once_with","page":"Home","title":"SimpleMock.called_once_with","text":"called_once_with(::Mock, args...; kwargs...) -> Bool\n\nReturn whether or not the Mock has been called exactly once with the given arguments.\n\n\n\n\n\n","category":"function"},{"location":"#SimpleMock.Call","page":"Home","title":"SimpleMock.Call","text":"Call(args...; kwargs...)\n\nRepresents a function call.\n\n\n\n\n\n","category":"type"},{"location":"#SimpleMock.has_call","page":"Home","title":"SimpleMock.has_call","text":"has_call(::Mock, ::Call) -> Bool\n\nSimiliar to called_with, but using a Call.\n\n\n\n\n\n","category":"function"},{"location":"#SimpleMock.has_calls","page":"Home","title":"SimpleMock.has_calls","text":"has_calls(::Mock, ::Calls...) -> Bool\n\nReturn whether or not the Mock has a particular ordered sequence of Calls.\n\n\n\n\n\n","category":"function"},{"location":"#SimpleMock.reset!","page":"Home","title":"SimpleMock.reset!","text":"reset!(::Mock)\n\nReset a Mock's call history and internal variables. Side effects and return values are preserved.\n\n\n\n\n\n","category":"function"},{"location":"#","page":"Home","title":"Home","text":"","category":"page"}]
}
