using Aqua

# `ambiguities` is disabled: SumTypes 0.5.9 generates single-parameter-completion
# `convert`/constructor methods that overlap at the degenerate `Uninit,Uninit`
# instantiation. See SUMTYPES_ISSUE.md.
Aqua.test_all(OptParse; ambiguities = false)
