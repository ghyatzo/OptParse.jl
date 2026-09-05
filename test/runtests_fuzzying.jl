using Test
using OptParse
using OptParse.SumResults
using Supposition
using Accessors: @set

include("fuzzying.jl")

function valid_record_structure(case)
    names = String[]
    function visit(spec, witness, depth)
        if spec isa RecordSpec
            witness isa RecordWitness || return false
            depth <= 3 && 1 <= length(spec.children) <= 4 || return false
            fields = first.(spec.children)
            fields == first.(witness.children) && allunique(fields) || return false
            return all(visit(s, w, depth + 1) for (s, w) in zip(last.(spec.children), last.(witness.children)))
        end
        if spec isa ModifiedOptionSpec
            if spec isa RepeatedSpec
                witness isa RepeatedWitness || return false
                0 <= spec.min <= length(witness.children) <= spec.max <= 4 || return false
                all(child.expected isa value_type(spec.child.value) for child in witness.children) || return false
            else
                witness isa PresenceWitness || return false
                isnothing(witness.child) || witness.child.expected isa value_type(spec.child.value) || return false
                spec isa DefaultSpec && !(spec.fallback isa value_type(spec.child.value)) && return false
            end
            push!(names, spec.child.name)
            return true
        end
        push!(names, spec.name)
        return (spec isa FlagSpec && witness isa FlagWitness) ||
            (spec isa OptionSpec && witness isa ValueWitness && witness.expected isa value_type(spec.value))
    end
    return visit(case.spec, case.witness, 1) &&
        1 <= length(names) <= 12 && names == ["--opt$i" for i in eachindex(names)]
end

function valid_record_layout(case)
    chunks = streams(case.spec, case.witness)
    sort(case.order) == traversal_order(chunks) || return false
    argv = render(case, case.order)
    return all(chunks) do stream
        isempty(stream) && return true
        positions = findall(==(first(first(stream))), argv)
        length(positions) == length(stream) || return false
        all(zip(positions, stream)) do (position, block)
            argv[position:(position + length(block) - 1)] == block
        end
    end
end

@testset "Fuzz harness" begin
    @testset "String option and flag" begin
        case = (
            spec = RecordSpec([
                "name" => OptionSpec("--name", StringSpec(true)),
                "verbose" => FlagSpec("--verbose"),
            ]),
            witness = RecordWitness([
                "name" => ValueWitness("Alice", "Alice"),
                "verbose" => FlagWitness(true),
            ]),
            order = [2, 1],
        )
        @test render(case, case.order) == ["--verbose", "--name", "Alice"]
        @test expected(case.spec, case.witness) === (name = "Alice", verbose = true)
        @test valid_records(case)
    end

    @testset "Integer types and bounds" begin
        for T in (Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Int128, UInt128)
            for value in (typemin(T), zero(T), typemax(T))
                case = (
                    spec = RecordSpec(["number" => OptionSpec("--number", IntegerSpec{T}())]),
                    witness = RecordWitness(["number" => ValueWitness(string(value), value)]),
                    order = [1],
                )
                argv = render(case, case.order)
                @test argv == ["--number", string(value)]
                @test expected(case.spec, case.witness) === (number = value,)
                @test valid_records(case)
                result = tryoptparse(compile(case.spec), argv)
                @test unwrap(result).number === value
            end
        end
    end

    @testset "Nested records" begin
        spec = RecordSpec([
            "network" => RecordSpec([
                "port" => OptionSpec("", IntegerSpec{UInt16}()),
                "logging" => RecordSpec(["verbose" => FlagSpec("")]),
            ]),
            "verbose" => FlagSpec(""),
        ])
        witness = RecordWitness([
            "network" => RecordWitness([
                "port" => ValueWitness("8080", UInt16(8080)),
                "logging" => RecordWitness(["verbose" => FlagWitness(false)]),
            ]),
            "verbose" => FlagWitness(true),
        ])
        case = (spec = assign_names(spec), witness = witness, order = [3, 1])
        @test valid_record_structure(case)
        @test spec.children[2].second.name == ""
        @test render(case, case.order) == ["--opt3", "--opt1", "8080"]
        @test expected(case.spec, case.witness) === (
            network = (port = UInt16(8080), logging = (verbose = false,)),
            verbose = true,
        )
        @test valid_records(case)

        absent = (
            spec = assign_names(RecordSpec([
                "outer" => RecordSpec([
                    "inner" => RecordSpec(["flag" => FlagSpec("")]),
                ]),
            ])),
            witness = RecordWitness([
                "outer" => RecordWitness([
                    "inner" => RecordWitness(["flag" => FlagWitness(false)]),
                ]),
            ]),
            order = Int[],
        )
        @test valid_record_structure(absent)
        @test render(absent, absent.order) == String[]
        @test expected(absent.spec, absent.witness) === (outer = (inner = (flag = false,),),)
        @test valid_records(absent)
    end

    @testset "Optional and defaulted options" begin
        for present in (false, true)
            case = (
                spec = assign_names(RecordSpec([
                    "settings" => RecordSpec([
                        "port" => OptionalSpec(OptionSpec("", IntegerSpec{UInt16}())),
                        "host" => DefaultSpec(OptionSpec("", StringSpec(true)), "localhost"),
                    ]),
                    "verbose" => FlagSpec(""),
                ])),
                witness = RecordWitness([
                    "settings" => RecordWitness([
                        "port" => PresenceWitness(present ? ValueWitness("8080", UInt16(8080)) : nothing),
                        "host" => PresenceWitness(present ? ValueWitness("server", "server") : nothing),
                    ]),
                    "verbose" => FlagWitness(true),
                ]),
                order = present ? [3, 1, 2] : [3],
            )
            @test valid_record_structure(case)
            @test render(case, case.order) == (present ?
                ["--opt3", "--opt1", "8080", "--opt2", "server"] : ["--opt3"])
            wanted = (settings = (port = present ? UInt16(8080) : nothing,
                host = present ? "server" : "localhost"), verbose = true)
            @test isequal(expected(case.spec, case.witness), wanted)
            @test valid_records(case)
        end

        absent = (
            spec = assign_names(RecordSpec([
                "settings" => RecordSpec([
                    "port" => OptionalSpec(OptionSpec("", IntegerSpec{UInt16}())),
                    "host" => DefaultSpec(OptionSpec("", StringSpec(true)), "localhost"),
                    "tags" => RepeatedSpec(OptionSpec("", StringSpec(true)), 0, 4),
                ]),
            ])),
            witness = RecordWitness([
                "settings" => RecordWitness([
                    "port" => PresenceWitness(nothing),
                    "host" => PresenceWitness(nothing),
                    "tags" => RepeatedWitness(ValueWitness[]),
                ]),
            ]),
            order = Int[],
        )
        @test valid_record_structure(absent)
        @test render(absent, absent.order) == String[]
        @test isequal(expected(absent.spec, absent.witness),
            (settings = (port = nothing, host = "localhost", tags = String[]),))
        @test expected(absent.spec, absent.witness).settings.tags isa Vector{String}
        @test valid_records(absent)
        @test unwrap(tryoptparse(compile(absent.spec), String[])).settings.tags isa Vector{String}
    end

    @testset "Repetition bounds and element types" begin
        for value_spec in (StringSpec(true), IntegerSpec{Int8}(), IntegerSpec{UInt128}())
            T = value_type(value_spec)
            values = T === String ? ["a", "b", "c", "d"] : T[0, 1, 2, typemax(T)]
            for (min_count, max_count, count) in ((0, 0, 0), (0, 4, 0), (0, 4, 1), (0, 4, 4), (2, 4, 2), (2, 4, 4))
                case = (
                    spec = assign_names(RecordSpec([
                        "values" => RepeatedSpec(OptionSpec("", value_spec), min_count, max_count),
                        "verbose" => FlagSpec(""),
                    ])),
                    witness = RecordWitness([
                        "values" => RepeatedWitness([ValueWitness(string(value), value) for value in values[1:count]]),
                        "verbose" => FlagWitness(true),
                    ]),
                    order = [fill(1, count); 2],
                )
                wanted_argv = String[]
                for value in values[1:count]
                    append!(wanted_argv, ["--opt1", string(value)])
                end
                push!(wanted_argv, "--opt2")
                @test valid_record_structure(case)
                @test render(case, case.order) == wanted_argv
                @test isequal(expected(case.spec, case.witness), (values = values[1:count], verbose = true))
                @test expected(case.spec, case.witness).values isa Vector{T}
                @test valid_records(case)
                result = tryoptparse(compile(case.spec), wanted_argv)
                @test unwrap(result).values isa Vector{T}
            end
        end
    end

    @testset "Occurrence interleaving" begin
        case = (
            spec = assign_names(RecordSpec([
                "left" => RecordSpec([
                    "tags" => RepeatedSpec(OptionSpec("", StringSpec(true)), 2, 2),
                    "host" => OptionSpec("", StringSpec(true)),
                ]),
                "right" => RecordSpec([
                    "numbers" => RepeatedSpec(OptionSpec("", IntegerSpec{Int8}()), 2, 2),
                    "port" => OptionalSpec(OptionSpec("", IntegerSpec{UInt16}())),
                ]),
                "verbose" => FlagSpec(""),
            ])),
            witness = RecordWitness([
                "left" => RecordWitness([
                    "tags" => RepeatedWitness([ValueWitness("a", "a"), ValueWitness("b", "b")]),
                    "host" => ValueWitness("server", "server"),
                ]),
                "right" => RecordWitness([
                    "numbers" => RepeatedWitness([ValueWitness("-1", Int8(-1)), ValueWitness("2", Int8(2))]),
                    "port" => PresenceWitness(nothing),
                ]),
                "verbose" => FlagWitness(true),
            ]),
            order = [1, 3, 2, 1, 5, 3],
        )
        @test valid_record_structure(case)
        @test streams(case.spec, case.witness) == [
            [["--opt1", "a"], ["--opt1", "b"]],
            [["--opt2", "server"]],
            [["--opt3", "-1"], ["--opt3", "2"]],
            Vector{String}[],
            [["--opt5"]],
        ]
        @test traversal_order(streams(case.spec, case.witness)) == [1, 1, 2, 3, 3, 5]
        @test render(case) == ["--opt1", "a", "--opt1", "b", "--opt2", "server",
            "--opt3", "-1", "--opt3", "2", "--opt5"]
        @test render(case, case.order) == ["--opt1", "a", "--opt3", "-1", "--opt2", "server",
            "--opt1", "b", "--opt5", "--opt3", "2"]
        @test isequal(expected(case.spec, case.witness), (
            left = (tags = ["a", "b"], host = "server"),
            right = (numbers = Int8[-1, 2], port = nothing),
            verbose = true,
        ))
        @test valid_record_layout(case)
        @test valid_records(case)
        @test_throws "Layout refers to an unknown stream" render(case, [6])
        @test_throws "Layout exhausts a stream" render(case, [4])
        @test_throws "Layout exhausts a stream" render(case, [1, 1, 1])
        @test_throws "Layout omits occurrences" render(case, [1])
    end

    @testset "Absent flags" begin
        case = (
            spec = RecordSpec([
                "verbose" => FlagSpec("--verbose"),
                "quiet" => FlagSpec("--quiet"),
            ]),
            witness = RecordWitness([
                "verbose" => FlagWitness(false),
                "quiet" => FlagWitness(false),
            ]),
            order = Int[],
        )
        @test render(case, case.order) == String[]
        @test render(case) == String[]
        @test valid_record_layout(case)
        @test expected(case.spec, case.witness) === (verbose = false, quiet = false)
        @test valid_records(case)
    end
end

@testset "Composition fuzzing (juliac=$(OptParse.juliac))" begin
    @check max_examples=200 db=Supposition.DirectoryDB(joinpath(@__DIR__, "SuppositionDB")) valid_record_structure(record_gen)
    @check max_examples=200 db=Supposition.DirectoryDB(joinpath(@__DIR__, "SuppositionDB")) valid_record_layout(ordered_record_gen)
    @check max_examples=200 db=Supposition.DirectoryDB(joinpath(@__DIR__, "SuppositionDB")) valid_records(ordered_record_gen)
end
