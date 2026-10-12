using Dates
using Test

@testset "should parse ISO dates" begin
    d = isodate()
    @test parse_ok(arg(d), ["2024-01-31"]) == Date(2024, 1, 31)
    @test parse_ok(arg(d), ["2024-2-1"]) == Date(2024, 2, 1) # DateFormat fields accept unpadded widths
    @test is_error(d("2024-13-01"))                          # not a calendar date
    @test is_error(d("31-01-2024"))
    @test is_error(d("2024-01-31T10:30"))                    # trailing input
    @test is_error(d(""))
end

@testset "should parse ISO date-times" begin
    s = isodatetime()
    @test parse_ok(arg(s), ["2024-01-31T10:30"]) == DateTime(2024, 1, 31, 10, 30)
    @test parse_ok(arg(s), ["2024-01-31T10:30:05.5"]) == DateTime(2024, 1, 31, 10, 30, 5, 500)
    @test parse_ok(arg(s), ["2024-01-31T10"]) == DateTime(2024, 1, 31, 10) # missing trailing fields
    @test parse_ok(arg(s), ["2024-01-31"]) == DateTime(2024, 1, 31)         # take their earliest values
    @test is_error(s("2024-01-31 10:30"))                  # space is not the format's separator
    @test is_error(s("2024-13-01T10:30"))
    @test is_error(s(""))
end

@testset "should parse with a caller-supplied format" begin
    d = dateformat(Date, "yyyy/mm/dd")
    @test parse_ok(arg(d), ["2024/01/31"]) == Date(2024, 1, 31)
    @test is_error(d("2024-01-31"))
    @test is_error(d("2024/01/31/01"))
end

@testset "should enforce inclusive after and before bounds" begin
    d = isodate(; after = Date(2024, 1, 1), before = Date(2024, 12, 31))
    @test parse_ok(arg(d), ["2024-01-01"]) == Date(2024, 1, 1)
    @test parse_ok(arg(d), ["2024-12-31"]) == Date(2024, 12, 31)

    err = unwrap_error(d("2023-12-31"))
    @test err isa OptParse.DateValError
    @test err.code == OptParse.DATE_TooEarly
    @test err.detail == "2024-01-01"

    err = unwrap_error(d("2025-01-01"))
    @test err.code == OptParse.DATE_TooLate
    @test err.detail == "2024-12-31"
end

@testset "should format errors and metavar" begin
    @test metavar(isodate()) == "DATE"
    @test metavar(isodatetime()) == "DATETIME"
    @test metavar(dateformat("WHEN", Date, "yyyy-mm-dd")) == "WHEN"

    err = unwrap_error(isodate()("yesterday"))
    @test sprint(OptParse.render_error, err) == "Expected a valid date, got yesterday"

    err = unwrap_error(isodate(; after = Date(2024, 1, 1))("2023-01-01"))
    @test sprint(OptParse.render_error, err) ==
        "Value 2023-01-01 is before the earliest allowed date: 2024-01-01"

    err = unwrap_error(isodate(; before = Date(2024, 12, 31))("2025-01-01"))
    @test sprint(OptParse.render_error, err) ==
        "Value 2025-01-01 is after the latest allowed date: 2024-12-31"
end

@testset "should be type stable" begin
    @test_opt isodate()
    @test_opt isodatetime()
    # Dates' parsing internals are not JET-clean on some Julia versions
    @test_opt target_modules = (OptParse,) isodate()("2024-01-31")
    @test_opt target_modules = (OptParse,) optparse(arg(isodate()), ["2024-01-31"])
end
