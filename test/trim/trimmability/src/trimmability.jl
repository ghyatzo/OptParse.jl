module trimmability

using OptParse

export @main

const greet = cmd(
	"greet",
	object((;
		cmd = @constant(:greet),
		name = option("-n", str()),
		port = option("-p", integer())
	))
)

const goodbye = cmd(
	"bye",
	object((;
		cmd = @constant(:bye),
		name = option("-n", str()),
		port = option("-p", integer())
	))
)

const simple = gate("-v")

const multiarg = multiple(arg(str()))

const opt = option("-d", "--depth", integer())

function @main(args::Vector{String})::Cint

	parser = or(simple, greet, multiarg, goodbye, opt)

	obj = argparse(parser, args)
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

function doaction(vec::OptParse.tval(multiarg))
	print(Core.stdout, "This is your list of strings: ")
	for str in vec
		print(Core.stdout, str)
	end
end

function doaction(verbose::OptParse.tval(simple))
	println(Core.stdout, "Yes, yes, you want to talk huh...")
end


end # module trimmability
