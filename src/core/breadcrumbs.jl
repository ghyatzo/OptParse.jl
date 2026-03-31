@enum BreadcrumbKind::UInt8 begin
    ObjectChild
    TupleChild
    AlternativeBranch
    CommandChild
end

struct Breadcrumb
    kind::BreadcrumbKind
    index::Int
end

