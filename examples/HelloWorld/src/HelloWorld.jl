module HelloWorld

using OptParse

 const hello = command(
     "hello",
     object((;
         cmd = @constant(:hello),
         name = option("-n", "--name", str("NAME")),
     ))
 )

 const goodbye = command(
     "goodbye",
     object((;
         cmd = @constant(:goodbye),
         name = option("-n", "--name", str("NAME")),
     ))
 )

 const parser = or(hello, goodbye)

 const Hello = resulttype(hello)
 const Goodbye = resulttype(goodbye)

 runaction(x::Hello) = println(Core.stdout, "Hello, $(x.name)!")
 runaction(x::Goodbye) = println(Core.stdout, "Goodbye, $(x.name)!")

 function (@main)(args::Vector{String})::Cint
     obj = argparse(parser, args)
     isnothing(obj) && return 1

     runaction(obj)
     return 0
 end

end # module HelloWorld
