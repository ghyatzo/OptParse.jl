@testset "SumResults" begin
    SR = OptParse.SumResults

    @testset "lazy construction leaves one parameter unset" begin
        ok = SR.Ok(1)
        err = SR.Err("boom")

        @test typeof(ok).parameters[1] === Int
        @test typeof(err).parameters[2] === String
        @test typeof(ok).parameters[2] === typeof(err).parameters[1]

        @test SR.unwrap(ok) === 1
        @test SR.unwrap_error(err) == "boom"
    end

    @testset "completion and widening" begin
        ok = SR.Ok(1)
        err = SR.Err("boom")

        # same success type, wider error type
        @test SR.Result{Int, String}(ok) isa SR.Result{Int, String}

        # success type widened to a supertype
        widened = SR.Result{Union{Int, String}, String}(ok)
        @test widened isa SR.Result{Union{Int, String}, String}
        @test SR.unwrap(widened) === 1

        # both parameters widened in one step
        both = SR.Result{Union{Int, String}, Union{String, Symbol}}(ok)
        @test both isa SR.Result{Union{Int, String}, Union{String, Symbol}}

        # the error variant widens the success type the same way
        @test SR.unwrap_error(SR.Result{Union{Int, String}, String}(err)) == "boom"

        # completing an already-unset boundary is a no-op
        sentinel = typeof(ok).parameters[2]
        @test SR.Result{Int, sentinel}(ok) === ok
    end

    @testset "Option" begin
        @test SR.Option{Int} === SR.Result{Int, Nothing}
        @test SR.unwrap(SR.some(3)) === 3
        @test SR.is_error(SR.none(Int))
        @test SR.base(SR.some(3)) === Some(3)
        @test SR.base(SR.none(Int)) === nothing
    end

    @testset "accessors" begin
        ok = SR.Ok(1)
        err = SR.Err("boom")

        @test !SR.is_error(ok)
        @test SR.is_error(err)
        @test SR.is_ok_and(==(1), ok)
        @test !SR.is_ok_and(==(2), ok)
        @test !SR.is_ok_and(==(1), err)
        @test_throws "unwrap called on an Err result" SR.unwrap(err)
        @test_throws "unwrap_error called on an Ok result" SR.unwrap_error(ok)
    end

    @testset "@? propagates the error variant" begin
        function plus_one(r)
            v = @? r
            return v + 1
        end

        @test plus_one(SR.Ok(1)) == 2

        propagated = plus_one(SR.Err(:bad))
        @test SR.is_error(propagated)
        @test SR.unwrap_error(propagated) === :bad
    end
end
