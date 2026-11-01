# Catalogue, Position, and Namespaces

## Shared structure

The catalogue is an implementation-independent representation of the parser
tree. Its nodes describe syntax in generic terms, such as options, flags,
arguments, commands, and composition. Usage, help, partial matching, and
suggestions consume this same structure.

A tree is represented by its root node. Every node also represents the complete
subtree rooted at that node, regardless of whether it belongs to a larger tree.

## Parsing location

The parsing context identifies three nodes in the same catalogue:

- **Catalogue:** the root of the complete syntax tree, unchanged during parsing.
- **Position:** the node currently being processed.
- **Namespace:** the node whose subtree defines the current parsing environment.

Position and namespace use the same node representation. They differ in how
they are updated: position follows parser traversal, while namespace changes
when parsing crosses a designated scope boundary. Moving to a child does not
necessarily change the namespace.

Subcommands are natural scope boundaries. The exact rules for choosing a
namespace root remain to be specified. Once chosen, the namespace consists of
all nodes in that root's subtree.

Parents prepare a child's position and environment before passing it a context.
Returned context updates are accepted on success. A failed attempt does not
change the accepted parsing context, but its location can accompany its error
for diagnostics.

## Tree queries

Query utilities accept a root node and inspect the tree rooted there. Examples
include collecting optionlike declarations or determining whether commands are
present. Queries do not distinguish between a whole catalogue, a namespace, or
a smaller subtree. The caller chooses the root.

Queries retain declaration nodes and their grouped aliases; consumers can
extract names or other metadata as needed.

## Consumers and recovery

Help uses position and namespace to select the relevant usage and help
information. Partial matching and suggestions query the supplied environment
and apply their own matching or ranking policies.

Parsing retains location information so diagnostics can use it directly. When
no parsing context is available, replaying arguments recovers the same position
and namespace. Replay is a recovery mechanism, not a separate definition of
scope.
