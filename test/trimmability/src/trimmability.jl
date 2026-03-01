module trimmability

using OptParse
using OptParse.WrappedUnions: @unionsplit, unwrap as unwrapunion
using OptParse.ErrorTypes: is_error, unwrap

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

const simple = flag("-v")

# function @main(args::Vector{String})::Cint
#     parser = or(greet, goodbye)
#     ctx = OptParse.Context(buffer=args, state=parser.initialState)

#     a = @unionsplit OptParse.parse(parser, ctx)
#     print(Core.stdout, a)

#     return 0
# end
safeprintln(str::String) = ccall(:jl_safe_printf, Cvoid, (Cstring, ), str * "\n")

# function @main(args::Vector{String})::Cint
#     parser = or(greet, goodbye)
#     inner = unwrapunion(parser)
#     S = OptParse.tstate(inner)
#     ctx = OptParse.Context{S}(buffer=args, state=parser.initialState)

#     pr = OptParse.parse(unwrapunion(parser), ctx)
#     if !is_error(pr)
#         st = OptParse.ℒ_nextstate(unwrap(pr))
#         _ = st
#         safeprintln("$(typeof(st))")
#     end

#     return 0
# end

function @main(args::Vector{String})::Cint
     parser = or(simple)
     inner = unwrapunion(parser)::OptParse.ConstrOr
     S = OptParse.tstate(inner)
     ctx = OptParse.Context{S}(buffer=args, state=parser.initialState)

     pr = OptParse.parse(inner, ctx)
     if !is_error(pr)
         st = OptParse.ℒ_nextstate(unwrap(pr))
         safeprintln("$(typeof(st))")
         res = OptParse.complete(inner, st)
         safeprintln("$(typeof(res))")
     end

     return 0
 end

# function @main(args::Vector{String})::Cint

# 	parser = or(simple)
# 	# parser = or(greet, goodbye)

# 	obj = @? argparse(parser, args)

# 	doaction(obj)

#     return 0
# end

function doaction(obj::OptParse.tval(greet))
	println(Core.stdout, "Hello, $(obj.name) ! you're $(obj.age) years old!")
end


function doaction(obj::OptParse.tval(goodbye))
	println(Core.stdout, "Goodbye, $(obj.name) ! See you in $(obj.solong) years!")
end


end # module trimmability
