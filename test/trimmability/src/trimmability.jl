module trimmability

using OptParse

const greet = command(
	"greet",
	object((;
		cmd = @constant(:greet),
		name = option("-n", str()),
		age = option("-a", integer())
	))
)

const goodbye = command(
	"bye",
	object((;
		cmd = @constant(:bye),
		name = option("-n", str()),
		solong = option("-a", integer())
	))
)

function @main(args::Vector{String})::Cint

	parser = or(greet, goodbye)

	obj = @? argparse(parser, args)

	if obj isa OptParse.tval(greet)
		println(Core.stdout, "Hello, $(obj.name) ! you're $(obj.age) years old!")
	elseif obj isa OptParse.tval(greet)
		println(Core.stdout, "Goodbye, $(obj.name) ! See you in $(obj.solong) years!")
	end
	
	# doaction(obj)
    return 0
end

function doaction(obj::OptParse.tval(greet))
	println(Core.stdout, "Hello, $(obj.name) ! you're $(obj.age) years old!")
end


function doaction(obj::OptParse.tval(goodbye))
	println(Core.stdout, "Goodbye, $(obj.name) ! See you in $(obj.solong) years!")
end


end # module trimmability
