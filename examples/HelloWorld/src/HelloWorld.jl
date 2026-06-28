module HelloWorld

using OptParse

name_parser = option("-n", "--name", str("NAME"))


@parser struct Hello
    "Name to greet"
    name = option("-n", "--name", str("NAME"))
end


@parser struct Goodbye
    "Name to wave goodbye"
    name = name_parser
end

const p = or(command("hello", lift(Hello)), command("goodbye", lift(Goodbye)))

runaction(x::Hello) = println(Core.stdout, "Hello, $(x.name)!")
runaction(x::Goodbye) = println(Core.stdout, "Goodbye, $(x.name)!")

function (@main)(args::Vector{String})::Cint
    obj = optparse(p, args)
    isnothing(obj) && return 1

    runaction(obj)
    return 0
end

end # module HelloWorld
