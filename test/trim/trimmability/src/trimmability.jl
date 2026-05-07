module trimmability

using OptParse

export @main

const greet = command(
	"greet",
	record((;
		cmd = @constant(:greet),
		name = option("-n", str()),
		port = option("-p", integer())
	))
)

const goodbye = command(
	"bye",
	record((;
		cmd = @constant(:bye),
		name = option("-n", str()),
		port = option("-p", integer())
	))
)

const simple = switch("-v")

const repeatedarg = many(arg(str()))

const opt = option("-d", "--depth", integer())

function @main(args::Vector{String})::Cint

	parser = or(simple, greet, repeatedarg, goodbye, opt)

	obj = optparse(parser, args)
	isnothing(obj) && return 1

	doaction(obj)

    return 0
end

function doaction(obj::OptParse.tval(greet))
	println(Core.stdout, "Hello, $(obj.name) ! Connecting to port $(obj.port)!")
end


function doaction(obj::OptParse.tval(goodbye))
	println(Core.stdout, "Goodbye, $(obj.name) ! disconnecting from port $(obj.port)!")
end

function doaction(vec::OptParse.tval(repeatedarg))
	print(Core.stdout, "This is your list of strings: ")
	for str in vec
		print(Core.stdout, str)
	end
end

function doaction(verbose::OptParse.tval(simple))
	println(Core.stdout, "Yes, yes, you want to talk huh...")
end


end # module trimmability
