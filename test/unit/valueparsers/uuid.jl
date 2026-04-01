@testset "UUIDVal" begin
    u = uuid(allowedVersions = [1, 4])
    u1 = string(uuid1())
    u4 = string(uuid4())
    u7 = string(uuid7())

    @test (@? u(u1)) == UUID(u1)
    @test uuid_version(@? u(u1)) == 1

    @test (@? u(u4)) == UUID(u4)
    @test uuid_version(@? u(u4)) == 4

    err = u(u7)
    @test is_error(err) && occursin("version", string(unwrap_error(err)))

    @test_opt u(u1)
end

@testset "UUIDVal with positional metavar" begin
    u = uuid("ID", allowedVersions = [1, 4])
    @test metavar(u) == "ID"
    @test uuid_version(@? u(string(uuid4()))) == 4
end
