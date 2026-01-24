module trimmability

using OptParse

function @main(args::Vector{String})::Cint

	parser = option("-n", str())
	name = @? argparse(parser, args)

	println(Core.stdout, "Hello, $name !")
    return 0
end

end # module trimmability
