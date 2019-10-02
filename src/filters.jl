"""
    max_depth(n::Int) -> Function

Create a filter that rejects when the current call depth is greater than `n`.
"""
max_depth(n::Int) = m::Metadata -> current_depth(m) <= n

"""
    min_depth(n::Int) -> Function

Create a filter that rejects when the current call depth is less than `n`.
"""
min_depth(n::Int) = m::Metadata -> current_depth(m) >= n

"""
    excluding(args...) -> Function

Create a filter that rejects when the calling function or module is in `args`.
"""
excluding(args...) = m::Metadata -> !(current_module(m) in args || current_function(m) in args)

"""
    including(args...) -> Function

Create a filter that rejects when the calling function or module is not in `args`.
"""
including(args...) = m::Metadata -> current_module(m) in args || current_function(m) in args
