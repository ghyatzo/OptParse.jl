module trimmability

using OptParse
using FastIdentifiers

@defid MyId ("i",
	            skip("-"),
	            :id(digits(6, pad=6)),
	            optional(".v", :version(digits(max=255)),
	                optional(".p", :participants(digits(max=2^16-1))))
	        )

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

const id = option("--ident", identifier(MyId))

function @main(args::Vector{String})::Cint

	parser = or(simple, greet, repeatedarg, goodbye, opt, id)

	obj = optparse(parser, args)
	isnothing(obj) && return 1

	doaction(obj)

    return 0
end

function doaction(obj::MyId)
	println(Core.stdout, "HELLO, it was a myID! $(shortcode(obj))")
end

function doaction(obj::valuetype(greet))
	println(Core.stdout, "Hello, $(obj.name) ! Connecting to port $(obj.port)!")
end


function doaction(obj::valuetype(goodbye))
	println(Core.stdout, "Goodbye, $(obj.name) ! disconnecting from port $(obj.port)!")
end

function doaction(vec::valuetype(repeatedarg))
	print(Core.stdout, "This is your list of strings: ")
	for str in vec
		print(Core.stdout, str)
	end
end

function doaction(verbose::valuetype(simple))
	println(Core.stdout, "Yes, yes, you want to talk huh...")
end

end
