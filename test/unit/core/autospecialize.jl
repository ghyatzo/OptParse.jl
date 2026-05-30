# Access the internal helper functions used by @autospecialize
using OptParse: _split_arg, _strip_type_params, _where_param_name, _extract_nested_params!, @autospecialize

@testset "Helper: _where_param_name" begin
    @test _where_param_name(:T) === :T
    @test _where_param_name(:(T <: Number)) === :T
    @test _where_param_name(42) === nothing
end

@testset "Helper: _split_arg" begin
    @test _split_arg(:(x::Int)) == (:x, :Int)
    @test _split_arg(:(p::AbstractParser{T, S})) == (:p, :(AbstractParser{T, S}))
    @test _split_arg(:(::Int)) == (nothing, :Int)
    @test _split_arg(:x) == (:x, nothing)
end

@testset "Helper: _strip_type_params" begin
    owned = Set{Symbol}([:T, :S])

    # Simple: strip all → nothing (fully emptied)
    @test _strip_type_params(:(Foo{T, S}), owned) === nothing
    # Partial: keep non-owned params
    @test _strip_type_params(:(Foo{T, B}), owned) == :(Foo{B})
    # Nested: Vector{ParseResult{T}} → Vector{ParseResult} → nothing (cascading empty)
    @test _strip_type_params(:(Vector{ParseResult{T}}), owned) === nothing
    # No owned params → unchanged
    @test _strip_type_params(:(Foo{A, B}), owned) == :(Foo{A, B})
    # Plain symbol not in owned → unchanged
    @test _strip_type_params(:X, owned) == :X
    # Plain symbol in owned → nothing
    @test _strip_type_params(:T, owned) === nothing
    # Mixed nested: Outer{Wrapper{T}, B} with owned={T} → Outer{B} (Wrapper{T} collapses)
    owned_t = Set{Symbol}([:T])
    @test _strip_type_params(:(Outer{Wrapper{T}, B}), owned_t) == :(Outer{B})
    # Subtype bound: Foo{T, <:Bar{S}} with owned={T, S} → nothing
    @test _strip_type_params(:(Foo{T, <:Bar{S}}), owned) === nothing
    # Partial subtype: Foo{<:Bar{T}, B} with owned={T} → Foo{B} (<:Bar{T} collapses)
    @test _strip_type_params(:(Foo{<:Bar{T}, B}), owned_t) == :(Foo{B})
end

@testset "Macro expansion" begin
    if OptParse.juliac
        @info "Skipping macro expansion tests (juliac=true, macro is passthrough)"
    end

    !OptParse.juliac && @testset "Full despecialize — two params from one arg" begin
        ex = @macroexpand @autospecialize pp function tryoptparse(
                pp::AbstractParser{T, S}, args::Vector{String}
            )::ParseResult{T} where {T, S}
            return T, S
        end

        d = splitdef(ex)

        # where clause should be gone
        @test isempty(get(d, :whereparams, []))
        # return type should be fully deleted
        @test !haskey(d, :rtype)
        # body should contain parameter extraction
        body_str = string(d[:body])
        @test occursin("(typeof(pp)).parameters[1]", body_str)
        @test occursin("(typeof(pp)).parameters[2]", body_str)
        # first arg should have @nospecialize with bare type
        arg1_str = string(d[:args][1])
        @test occursin("nospecialize", arg1_str)
        @test occursin("AbstractParser", arg1_str)
    end

    !OptParse.juliac && @testset "Multiple targets" begin
        ex = @macroexpand @autospecialize pp ctx function parse(
                pp::AbstractParser{T, S}, ctx::Context{S}
            )::InnerParseResult{S} where {T, S}
            return nothing
        end

        d = splitdef(ex)

        @test isempty(get(d, :whereparams, []))
        body_str = string(d[:body])
        # T from pp at position 1
        @test occursin("(typeof(pp)).parameters[1]", body_str)
        # S from pp at position 2 (first encounter wins)
        @test occursin("(typeof(pp)).parameters[2]", body_str)
        # S should NOT be extracted again from ctx (already owned)
        @test !occursin("(typeof(ctx))", body_str)
        # Both args should be @nospecialize'd
        arg_strs = string.(d[:args])
        @test all(s -> occursin("nospecialize", s), arg_strs)
    end

    !OptParse.juliac && @testset "No where clause — just adds @nospecialize" begin
        ex = @macroexpand @autospecialize parser function build_help_doc(parser, argv)
            return nothing
        end

        d = splitdef(ex)

        # No where clause before, none after
        @test isempty(get(d, :whereparams, []))
        # parser should have @nospecialize
        @test occursin("nospecialize", string(d[:args][1]))
        # argv should NOT
        @test !occursin("nospecialize", string(d[:args][2]))
    end

    !OptParse.juliac && @testset "Bounded where params" begin
        ex = @macroexpand @autospecialize x function g(
                x::Foo{A}
            ) where {A <: Number}
            return A
        end

        d = splitdef(ex)

        @test isempty(get(d, :whereparams, []))
        body_str = string(d[:body])
        @test occursin("(typeof(x)).parameters[1]", body_str)
    end

    !OptParse.juliac && @testset "Nested type params — ModWithDefault-style" begin
        # S is nested inside Wrapper{S} at curly position 2
        ex = @macroexpand @autospecialize p function parse(
                p::Outer{T, Wrapper{S}, P}, ctx::Context{Wrapper{S}}
            )::InnerResult{Wrapper{S}} where {T, S, P}
            return S
        end

        d = splitdef(ex)

        # All where params should be owned and removed
        @test isempty(get(d, :whereparams, []))
        body_str = string(d[:body])
        # T from position 1 (direct)
        @test occursin("(typeof(p)).parameters[1]", body_str)
        # S from position 2, nested position 1
        @test occursin("parameters[2]", body_str) && occursin("parameters[1]", body_str)
        # P from position 3 (direct)
        @test occursin("(typeof(p)).parameters[3]", body_str)
        # Return type fully deleted
        @test !haskey(d, :rtype) || d[:rtype] === nothing
    end

    @testset "Static mode passthrough" begin
        # When juliac is true the macro should be identity.
        # We can't toggle juliac at test time, but we can verify
        # that with no targets the function passes through unchanged.
        ex = @macroexpand @autospecialize function f(x::Int) where {T}
            return x
        end

        d = splitdef(ex)
        # No targets → passthrough, where clause preserved
        @test !isempty(get(d, :whereparams, []))
    end
end


@testset "Runtime behavior" begin

    # Define test types to exercise the macro at runtime
    abstract type TestBase{T, S} end
    struct TestConcrete{T, S} <: TestBase{T, S}
        val::T
    end

    @autospecialize x function extract_params(x::TestBase{T, S}) where {T, S}
        return (T, S)
    end

    @test extract_params(TestConcrete{Int, String}(42)) == (Int, String)
    @test extract_params(TestConcrete{Float64, Symbol}(1.0)) == (Float64, Symbol)

    @autospecialize x function with_return_type(x::TestBase{T, S})::Tuple where {T, S}
        return (T, S)
    end

    @test with_return_type(TestConcrete{Int, String}(42)) == (Int, String)

    @autospecialize x function partial_despec(x::TestBase{T, S}, y::Vector{S}) where {T, S}
        return (T, S, y)
    end

    @test partial_despec(TestConcrete{Int, String}(42), String["a"]) == (Int, String, ["a"])

    # Nested type param extraction
    struct Wrapper{X}
        inner::X
    end
    struct Outer{T, W, P}
        w::W
        p::P
    end

    @autospecialize o function nested_extract(o::Outer{T, Wrapper{S}, P}) where {T, S, P}
        return (T, S, P)
    end

    obj = Outer{Int, Wrapper{String}, Float64}(Wrapper("hi"), 1.0)
    @test nested_extract(obj) == (Int, String, Float64)
end
