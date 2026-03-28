using Preferences: @load_preference
const juliac = @load_preference("juliac", false)

# Minimal juliac-compatible IO implementation for stdin/stdout/stderr
struct RawIO <: Base.IO
    fd::RawFD
end

function Base.unsafe_write(io::RawIO, buf::Ptr{UInt8}, count::UInt)
    n = @ccall write(io.fd::Cint, buf::Ptr{Cvoid}, count::Csize_t)::Cssize_t
    return n % Int
end

function Base.write(io::RawIO, byte::UInt8)
    n = @ccall write(io.fd::Cint, Ref(byte)::Ptr{Cvoid}, 1::Csize_t)::Cssize_t
    return n % Int
end

# TODO: This could potentially hook into `Base.readbytes!` instead to make this more
# generally useful but for the usecase here we just need to read all the bytes until EOF.
function Base.read(io::RawIO)
    @assert io === stdin
    bytes = UInt8[]
    bufsize = 1024
    buf = Vector{UInt8}(undef, bufsize)
    while true
        nread = @ccall read(io.fd::Cint, buf::Ptr{Cvoid}, bufsize::Csize_t)::Cssize_t
        nread == -1 && systemerror("read")
        nread == 0 && break # eof
        append!(bytes, @view(buf[1:nread]))
    end
    return bytes
end

# juliac-compatible `Base.printstyled`
function printstyled_juliac(io::RawIO, str::String; bold = false, color::Symbol = :normal)
    # TODO: Base.printstyled splits on \n and prints each line separately
    @assert !occursin('\n', str)
    use_color = isatty(io)
    if use_color
        color === :red && write(io, "\e[31m")
        color === :green && write(io, "\e[32m")
        color === :blue && write(io, "\e[34m")
        color === :normal && write(io, "\e[0m")
        bold && write(io, "\e[1m")
    end
    print(io, str)
    if use_color
        bold && write(io, "\e[22m")
        color in (:red, :green, :blue) && write(io, "\e[39m")
    end
    return
end

function isatty(io::RawIO)
    return (@ccall isatty(io.fd::Cint)::Cint) == 1
end
supports_color(io::RawIO) = isatty(io)

# juliac-compatible `Base.showerror`
# TODO: Special case for JuliaSyntax.ParseError
function sprint_showerror_juliac(err::Exception)
    if err isa SystemError
        return "SystemError: " * err.prefix * ": " * Libc.strerror(err.errnum)
    elseif err isa AssertionError
        # sprint uses dynamic dispatch
        io = IOBuffer()
        showerror(io, err)
        return String(take!(io))
    else
        return string(typeof(err))
    end
end

# juliac-compatible print(::IO, ::VersionNumber) with explicitly `@inline`d `join` calls...
function print_vnum_juliac(io::IO, v::VersionNumber)
    v == typemax(VersionNumber) && return print(io, "∞")
    print(io, v.major)
    print(io, '.')
    print(io, v.minor)
    print(io, '.')
    print(io, v.patch)
    if !isempty(v.prerelease)
        print(io, '-')
        @inline join(io, v.prerelease, '.')
    end
    if !isempty(v.build)
        print(io, '+')
        @inline join(io, v.build, '.')
    end
    return
end

@static if juliac
    include("juliac.jl")
    const stdin = RawIO(RawFD(0))
    const stdout = RawIO(RawFD(1))
    const stderr = RawIO(RawFD(2))
    const printstyled = printstyled_juliac
    const sprint_showerror = sprint_showerror_juliac
    const print_vnum = print_vnum_juliac
else
    # const stdin = Base.stdin
    # const stdout = Base.stdout
    # const stderr = Base.stderr
    const run_cmd = Base.run
    const printstyled = Base.printstyled
    sprint_showerror(err::Exception) = sprint(showerror, err)
    const print_vnum = Base.print
end

supports_color(io) = get(io, :color, false)