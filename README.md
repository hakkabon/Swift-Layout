# SwiftLayout

A SwiftUI-facing wrapper around [`Layout`](https://github.com/hakkabon/Layout), a
Sugiyama-style hierarchical graph layout engine written in Rust. This package owns
the Swift half of the FFI boundary: it turns raw engine output (positions, routed
edges, arrowhead geometry, an obstacle-free label position) into something a
SwiftUI view can render directly, and gives you two ready-made views to do that
rendering.

If you're looking for the layout algorithm itself — ranking, crossing reduction,
coordinate assignment, edge routing — that lives in the `Layout` repo, not here.
This package is deliberately thin: domain-agnostic FFI wrapper plus rendering, no
graph algorithm code of its own.

## Installation

Add this package as a Swift Package Manager dependency:

```swift
dependencies: [
    .package(url: "https://github.com/hakkabon/Swift-Layout.git", from: "0.1.0")
]
```

`Package.swift` here in turn pulls in a prebuilt `LayoutFFI.xcframework` binary
target from the `Layout` repo's releases — you don't need a Rust toolchain to
build against this package, only to build the engine itself. That binary target
is updated automatically by `Layout`'s release workflow whenever a new tag is
pushed there (see zero-touch automation, below), so pin this package to a
specific release rather than tracking `main` if you want reproducible builds.

## The three moving pieces

Getting a domain graph (a syntax tree, an FSA, whatever) on screen is three
steps, each corresponding to one type in this package:

### 1. `GraphFlattening` — describe how to walk your graph

The engine only knows about `FfiNode`/`FfiEdge` — opaque `UInt64` ids, sizes,
optional label dimensions. Your domain graph is presumably a tree of reference
types with real identity. Bridge the two by conforming to `GraphFlattening`:

```swift
struct MyTreeFlattener: GraphFlattening {
    let root: MyTreeNode

    func flatten() -> (nodes: [FfiNode], edges: [FfiEdge], lookup: [UInt64: MyTreeNode]) {
        let ids = NodeIDAllocator()
        var ffiNodes: [FfiNode] = []
        var ffiEdges: [FfiEdge] = []
        var lookup: [UInt64: MyTreeNode] = [:]

        func visit(_ node: MyTreeNode) {
            let id = ids.id(for: node)
            ffiNodes.append(FfiNode(id: id, width: 80, height: 28))
            lookup[id] = node
            for child in node.children {
                ffiEdges.append(FfiEdge(from: id, to: ids.id(for: child), labelWidth: nil, labelHeight: nil))
                visit(child)
            }
        }
        visit(root)
        return (ffiNodes, ffiEdges, lookup)
    }
}
```

`NodeIDAllocator` hands out a stable `UInt64` per object (keyed by
`ObjectIdentifier`) for the lifetime of one `flatten()` call. As long as your
traversal order is deterministic — walking arrays in a fixed order, not iterating
a `Set` — the same node gets the same id across repeated `flatten()` calls on an
unchanged graph. That matters: it's what lets `GraphLayoutCoordinator.nodes`
(which conforms to `Identifiable` via that id) preserve SwiftUI view identity
across a relayout, instead of tearing down and recreating every node view.

Set `labelWidth`/`labelHeight` on an `FfiEdge` if that edge has a label you want
placed obstacle-free — the engine reserves space for it and hands back a
`labelPosition` on the resulting route (see below). Leave them `nil` for
unlabeled edges. Return the corresponding display text from your flattener's
`label(for:)` method; its default implementation returns `nil`, so existing
unlabelled conformances need no changes.

See `Sample-App`'s `GraphFlattening/` folder for four real conformances (syntax
tree, FSA/DFA, SPPF, GSS) — SPPF and GSS in particular show how to flatten a DAG
with shared/merged nodes rather than a plain tree.

### 2. `GraphLayoutCoordinator` — runs layout, publishes the result

```swift
@StateObject var coordinator = GraphLayoutCoordinator<MyTreeNode>()

// ...
let config = FfiConfig(
    hGap: 24, vGap: 48,
    relaxPasses: 4, sweeps: 4,
    algorithm: .brandesKopf,   // or .medianRelax
    routing: .bezier,          // or .straight / .orthogonal
    direction: .topToBottom    // or .leftToRight
)
await coordinator.relayout(MyTreeFlattener(root: root), config: config)
```

`relayout` runs the actual FFI call on a detached background task (layout of a
large graph is not free), then republishes `nodes`, `routes`, `selfLoops`,
`engineBounds`, and `isLayingOut` back on the main actor. It's `@MainActor`
itself and `ObservableObject`, so a SwiftUI view holding one as `@StateObject`
just works — trigger `relayout` from `.task`/`.onChange`, not from `body`.

A couple of things worth knowing about what comes back:

- **`nodes: [PositionedNode<Node>]`** pairs each domain node with the `(x, y)`
  the engine assigned it. The coordinate space is centered at the graph's own
  origin (not top-left) — see `GraphPlacement` below for how that gets mapped
  onto an actual canvas.
- **`routes: [PositionedEdgeRoute]`** carries the polyline/curve points for each
  edge, plus (when the engine computed them) `arrowhead` — tip and both wing
  vertices, ready to fill as a triangle — and `labelPosition`. Both render for
  free if you use `GraphVisualizationView` below; if you're writing a custom
  renderer, prefer these over re-deriving an arrowhead angle from `points` or
  eyeballing a label position from a midpoint.
- **`engineBounds`** is the graph's true bounding box, accounting for each
  node's actual width/height — not just node centers. This is what
  `GraphPlacement`/`AnchoredGraphView` use to fit the graph onto a canvas.
- Relayout failures surface as `lastError: GraphLayoutError?`, which
  `GraphVisualizationView` already presents as an alert — you don't need to
  handle it separately unless you want custom error UI.

### 3. Rendering: `GraphVisualizationView` or `AnchoredGraphView`

`GraphVisualizationView` draws exactly what the coordinator currently has: nodes
as whatever SwiftUI content you provide per node, edges and arrowheads via
`Canvas`, and edge labels at the engine-provided obstacle-free positions. Pass
`edgeLabelContent` to customize label styling, or use the default material pill.
It takes a flat `offset: CGSize` if you want to place the graph yourself.

`AnchoredGraphView` is the one you actually want in most cases — it wraps
`GraphVisualizationView` in a `GeometryReader` and uses `GraphPlacement.offset`
to fit the graph against a `GraphAnchor` (`.center`, `.top`, `.bottom`, `.left`,
`.right`) within whatever space SwiftUI gives it, recomputing on every canvas
resize:

```swift
AnchoredGraphView(coordinator: coordinator, anchor: .center) { node in
    AnyView(
        Text(node.label)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(.background))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.primary))
    )
}
```

`GraphPlacement.offset` is a pure function of `(boundingBox, canvasSize, anchor,
padding, nodeMargin)` with no FFI dependency — worth knowing if you want to unit
test placement logic without spinning up the layout engine.

## Coordinate system notes

- The engine centers its own output at `(0, 0)`; `GraphPlacement` is what
  translates that into positive on-screen coordinates. If you see nodes or
  edges vanish, check that you're applying the same `offset` to both — negative
  coordinates rendered without an offset get silently clipped by SwiftUI.
- Y grows downward, matching SwiftUI/`Canvas`/`.position(x:y:)` convention, not
  a math/Cartesian one.

## Threading

`GraphLayoutCoordinator` is `@MainActor`. `relayout` is `async` and does the
actual FFI call inside `Task.detached`, so a large graph's layout computation
doesn't block the main thread — but the coordinator's published properties are
only ever mutated back on the main actor, so it's safe to observe from a
SwiftUI view without any extra synchronization on your part.

## Versioning

This package's `Package.swift` pins a specific `Layout` release tag + checksum
for its binary target. `Layout`'s CI pushes an automated commit here bumping
that pin whenever a new tag is released there — see `Layout`'s
`release-to-swift.yml` workflow. That means `main` here can move without any
change to this package's own source; if you depend on this package, pin to a
tagged release of *this* repo rather than `main` for reproducible builds.

## See also

- [`Layout`](https://github.com/hakkabon/Layout) — the Rust engine itself:
  algorithm details, `FfiConfig` tuning, complexity notes.
- [`Sample-App`](https://github.com/hakkabon/Sample-App) — a SwiftUI app
  exercising all of the above across four real graph kinds (syntax trees, FSA/DFA,
  SPPF, GSS), including self-loop handling and multiple layout algorithms.
