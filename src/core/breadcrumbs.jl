@enum BreadcrumbKind::UInt8 begin
    BREADCRUMB_TupleChild
    BREADCRUMB_AlternativeBranch
    BREADCRUMB_CommandChild
end

struct Breadcrumb
    kind::BreadcrumbKind
    index::Int
end

@inline usage_alternative_branch(i) = Breadcrumb(BREADCRUMB_AlternativeBranch, i)
@inline usage_tuple_child(i) = Breadcrumb(BREADCRUMB_TupleChild, i)
@inline usage_command_boundary() = Breadcrumb(BREADCRUMB_CommandChild, 1)
