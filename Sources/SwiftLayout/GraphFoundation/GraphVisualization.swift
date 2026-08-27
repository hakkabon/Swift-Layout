//
//  GraphVisualization.swift
//  Test-FFI
//
//  Created by Ulf Akerstedt-Inoue on 2026/08/14.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation
import SwiftUI

/// Renders whatever the coordinator currently has laid out. Generic over
/// the domain node type so the same view works for syntax trees, FSA
/// states, SPPF nodes, or GSS nodes — only the flattener passed in at the
/// call site differs.

/// Important: Translate the drawing context inside the Canvas (or pass
/// the placement offset into GraphVisualizationView) so all strokes occur
/// in positive canvas space.

public struct GraphVisualizationView<Node: AnyObject>: View {
    @ObservedObject var coordinator: GraphLayoutCoordinator<Node>
    var offset: CGSize = .zero
    let nodeContent: (Node) -> AnyView
    let edgeLabelContent: (String) -> AnyView

    public var body: some View {
        ZStack {
            Canvas { context, size in
                // Translate the canvas context by the placement offset so
                // negative engine coordinates become positive canvas coordinates!
                context.translateBy(x: offset.width, y: offset.height)

                for route in coordinator.routes {
                    guard let first = route.points.first else { continue }
                    var path = Path()
                    path.move(to: first)

                    if route.points.count == 2 {
                        path.addLine(to: route.points[1])
                    } else if coordinator.routingStyle == .bezier && route.points.count >= 4 && (route.points.count - 1) % 3 == 0 {
                        var i = 1
                        while i + 2 < route.points.count {
                            path.addCurve(
                                to: route.points[i + 2],
                                control1: route.points[i],
                                control2: route.points[i + 1]
                            )
                            i += 3
                        }
                    } else {
                        // Fallback polyline for orthogonal or multi-point edges
                        for point in route.points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }

                    context.stroke(path, with: .color(.primary.opacity(0.8)), lineWidth: route.reversed ? 2.0 : 1.5)

                    // Arrowhead, if the engine computed one for this route
                    // (it doesn't for a self-loop's own tip today). Purely
                    // geometric — tip + two wing vertices — so it belongs
                    // here rather than in each call site's node content.
                    if let ah = route.arrowhead {
                        var arrowPath = Path()
                        arrowPath.move(to: CGPoint(x: CGFloat(ah.left.x), y: CGFloat(ah.left.y)))
                        arrowPath.addLine(to: CGPoint(x: CGFloat(ah.tip.x), y: CGFloat(ah.tip.y)))
                        arrowPath.addLine(to: CGPoint(x: CGFloat(ah.right.x), y: CGFloat(ah.right.y)))
                        arrowPath.closeSubpath()
                        context.fill(arrowPath, with: .color(.primary.opacity(0.8)))
                    }
                }
            }

            ForEach(coordinator.nodes) { node in
                nodeContent(node.source)
                    .position(x: node.x + offset.width, y: node.y + offset.height)
            }

            ForEach(coordinator.routes) { route in
                if let label = route.label, let position = route.labelPosition {
                    edgeLabelContent(label)
                        .position(
                            x: position.x + offset.width,
                            y: position.y + offset.height
                        )
                }
            }

            if coordinator.isLayingOut {
                ProgressView().padding(8).background(.thinMaterial).cornerRadius(8)
            }
        }
        .alert(item: $coordinator.lastError) { error in
            Alert(title: Text("Layout failed"), message: Text(error.errorDescription ?? "Unknown error"))
        }
    }
    
    // Explicitly write this to make it accessible outside the module
    public init(
        coordinator: GraphLayoutCoordinator<Node>,
        offset: CGSize = .zero,
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
        self.offset = offset
        self.nodeContent = nodeContent
        self.edgeLabelContent = edgeLabelContent
    }
}

extension GraphLayoutError: Identifiable {
    public var id: String { errorDescription ?? "unknown" }
}
