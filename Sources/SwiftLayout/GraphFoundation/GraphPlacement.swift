//
//  GraphPlacement.swift
//  Test-FFI
//
//  Created by Ulf Akerstedt-Inoue on 2026/08/14.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import SwiftUI
import SwiftLayout

///  General idea: Positions an already-laid-out graph within a canvas
///  rectangle.
///
///  The layout engine's coordinate-assignment phase always centers its
///  output at (0,0) (see `assign_coordinates` in coordinates.rs — it
///  subtracts the bounding box's own center from every node before
///  returning). That means placement is a pure Swift-side problem: given
///  the graph's bounding box (in that already-centered coordinate space)
///  and the canvas size SwiftUI actually gives us, compute one translation
///  that aligns the box against the requested anchor, and apply it as a
///  single `.offset()` on the whole rendered graph. Nodes and edge routes
///  move together for free, since it's a post-layout visual transform, not
///  a re-layout — no FFI call involved.

/// Where to anchor the graph within its canvas. The non-`center` cases
/// each align flush to one edge (with `padding`) while staying centered
/// on the other axis — e.g. `.top` centers horizontally and pins the
/// graph's top edge near the canvas's top edge.
public enum GraphAnchor: String, CaseIterable, Identifiable {
    case center = "Center"
    case top = "Top"
    case bottom = "Bottom"
    case left = "Left"
    case right = "Right"

    public var id: String { rawValue }
}

public enum GraphPlacement {
    /// Computes the `(dx, dy)` to add to every raw node/route coordinate
    /// so the graph sits inside `canvasSize` per `anchor`.
    ///
    /// - Parameters:
    ///   - boundingBox: The graph's bounding box in its own (already
    ///     origin-centered) coordinate space, or `nil` if there's nothing
    ///     laid out yet — see `boundingBox` below. Note this is NOT the
    ///     same thing as `CGRect.isEmpty`: a legitimate single-column or
    ///     single-row graph (e.g. a linear chain of states) has a
    ///     genuinely zero-width or zero-height box, which is a real,
    ///     placeable box, not an absent one.
    ///   - canvasSize: The actual rendered size of the canvas (from
    ///     `GeometryReader`), assumed to have its origin at top-left, as
    ///     SwiftUI's `.position(x:y:)` does.
    ///   - nodeMargin: `boundingBox` now reports the layout engine's own
    ///     bounds (see `GraphLayoutCoordinator.engineBounds`), which
    ///     already account for each node's real width/height — so this is
    ///     no longer compensating for missing size data. It's purely
    ///     visual breathing room between the outermost node and the
    ///     canvas edge; set it to `0` for a tight fit.
    public static func offset(
        boundingBox: CGRect?,
        canvasSize: CGSize,
        anchor: GraphAnchor,
        padding: CGFloat = 24,
        nodeMargin: CGFloat = 24
    ) -> CGSize {
        guard let boundingBox else { return .zero }
        let box = boundingBox.insetBy(dx: -nodeMargin, dy: -nodeMargin)

        let graphCenter = CGPoint(x: box.midX, y: box.midY)
        let canvasCenter = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let centeredDX = canvasCenter.x - graphCenter.x
        let centeredDY = canvasCenter.y - graphCenter.y

        switch anchor {
        case .center:
            return CGSize(width: centeredDX, height: centeredDY)
        case .top:
            return CGSize(width: centeredDX, height: padding - box.minY)
        case .bottom:
            return CGSize(width: centeredDX, height: (canvasSize.height - padding) - box.maxY)
        case .left:
            return CGSize(width: padding - box.minX, height: centeredDY)
        case .right:
            return CGSize(width: (canvasSize.width - padding) - box.maxX, height: centeredDY)
        }
    }
}

/// Drop-in replacement for `GraphVisualizationView` that additionally
/// anchors the rendered graph within whatever space it's given, instead
/// of relying on SwiftUI's own (unspecified, content-dependent) sizing
/// for a `.position()`-based `ZStack`.
public struct AnchoredGraphView<Node: AnyObject>: View {
    @ObservedObject var coordinator: GraphLayoutCoordinator<Node>
    var anchor: GraphAnchor = .center
    var padding: CGFloat = 24
    var nodeMargin: CGFloat = 24
    let nodeContent: (Node) -> AnyView
    let edgeLabelContent: (String) -> AnyView

    public var body: some View {
        // Translate the drawing context inside the Canvas (or pass the placement
        // offset into GraphVisualizationView) so all strokes occur in positive
        // canvas space $[0 \dots \text{width}, 0 \dots \text{height}]$.
        GeometryReader { proxy in
            let offset = GraphPlacement.offset(
                boundingBox: coordinator.boundingBox,
                canvasSize: proxy.size,
                anchor: anchor,
                padding: padding,
                nodeMargin: nodeMargin
            )

            GraphVisualizationView(
                coordinator: coordinator,
                offset: offset,
                nodeContent: nodeContent,
                edgeLabelContent: edgeLabelContent
            )
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.2), value: offset)
        }
    }
    
    // Explicitly write this to make it accessible outside the module
    public init(
        coordinator: GraphLayoutCoordinator<Node>,
        anchor: GraphAnchor = .center,          // Default value included!
        padding: CGFloat = 24,                  // Default value included!
        nodeMargin: CGFloat = 24,               // Default value included!
        nodeContent: @escaping (Node) -> AnyView,
        edgeLabelContent: @escaping (String) -> AnyView = { label in
            AnyView(
                Text(label)
                    .font(.caption)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
            )
        }
    ) {
        self._coordinator = ObservedObject(wrappedValue: coordinator)
        self.anchor = anchor
        self.padding = padding
        self.nodeMargin = nodeMargin
        self.nodeContent = nodeContent
        self.edgeLabelContent = edgeLabelContent
    }
}
