//
//  Coordinator.swift
//  Test-FFI
//
//  Created by Ulf Akerstedt-Inoue on 2026/08/12.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation

/// A domain node (`Source`) plus the position the layout engine assigned
/// it. This is what the SwiftUI view actually renders — it never sees
/// `FfiPosition` or FFI ids directly.
public struct PositionedNode<Source: AnyObject>: Identifiable {
    public let id: UInt64
    public let source: Source
    public let x: CGFloat
    public let y: CGFloat
}

public struct PositionedEdgeRoute: Identifiable {
    public let id: UUID = UUID()
    public let from: UInt64
    public let to: UInt64
    public let reversed: Bool
    public let isSelfLoop: Bool
    public let points: [CGPoint]
    /// Domain-provided label text associated with this route.
    public let label: String?
    /// Precomputed arrowhead geometry (tip + wing vertices) at the target
    /// end, straight from the layout engine. `GraphVisualizationView`
    /// draws this directly; callers building a custom renderer can use it
    /// too instead of re-deriving an arrowhead from `points`' tangent.
    public let arrowhead: FfiArrowhead?
    /// Obstacle-free label center position computed by the layout engine,
    /// if the originating edge had label dimensions. Prefer this over
    /// eyeballing a midpoint from `points` when placing an edge label.
    public let labelPosition: CGPoint?
}

public enum GraphLayoutError: Error, LocalizedError {
    case engine(FfiLayoutError)
    public var errorDescription: String? {
        switch self {
        case .engine(let e): return "\(e)"
        }
    }
}

/// Runs the layout engine off the main thread and publishes a
/// domain-agnostic, positioned graph for the view to render.
@MainActor
public final class GraphLayoutCoordinator<Node: AnyObject>: ObservableObject {
    @Published public private(set) var nodes: [PositionedNode<Node>] = []
    @Published public private(set) var routes: [PositionedEdgeRoute] = []
    @Published public private(set) var selfLoops: [FfiEdge] = []
    @Published public private(set) var isLayingOut = false
    @Published public private(set) var routingStyle: FfiRoutingStyle = .straight
    @Published public var lastError: GraphLayoutError?
    /// The graph's bounding box exactly as computed by the layout engine —
    /// accounts for each node's real width/height, not just its center.
    /// `nil` until the first successful `relayout`. See `boundingBox`
    /// below, which is what most callers should actually use.
    @Published public private(set) var engineBounds: CGRect?

    // public initializer
    public init() {}

    /// Re-runs layout for whatever `flattener` currently describes.
    public func relayout<F: GraphFlattening>(_ flattener: F, config: FfiConfig) async where F.Node == Node {
        let (ffiNodes, ffiEdges, lookup) = flattener.flatten()
        var labelsByEndpoints: [EdgeEndpoints: [String?]] = [:]
        for edge in ffiEdges {
            labelsByEndpoints[EdgeEndpoints(from: edge.from, to: edge.to), default: []]
                .append(flattener.label(for: edge))
        }
        guard !ffiNodes.isEmpty else {
            nodes = []
            routes = []
            selfLoops = []
            engineBounds = nil
            return
        }

        isLayingOut = true
        defer { isLayingOut = false }

        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try layout(nodes: ffiNodes, edges: ffiEdges, config: config)
            }.value

            // Rejoin each FfiPosition back to its domain node
            nodes = result.positions.compactMap { pos in
                guard let source = lookup[pos.id] else { return nil }
                return PositionedNode(id: pos.id, source: source, x: CGFloat(pos.x), y: CGFloat(pos.y))
            }
            routes = result.routes.map { route in
                // Cycle breaking may reverse an edge internally. The route's
                // endpoints then describe the laid-out direction, while the
                // flattener supplied the label in the original direction.
                let endpoints = route.reversed
                    ? EdgeEndpoints(from: route.to, to: route.from)
                    : EdgeEndpoints(from: route.from, to: route.to)
                let label = labelsByEndpoints[endpoints]?.isEmpty == false
                    ? labelsByEndpoints[endpoints]!.removeFirst()
                    : nil
                return PositionedEdgeRoute(
                    from: route.from,
                    to: route.to,
                    reversed: route.reversed,
                    isSelfLoop: route.isSelfLoop,
                    points: route.waypoints.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) },
                    label: label,
                    arrowhead: route.arrowhead,
                    labelPosition: route.labelPosition.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
                )
            }
            selfLoops = result.selfLoops
            routingStyle = config.routing
            engineBounds = CGRect(
                x: CGFloat(result.bounds.minX),
                y: CGFloat(result.bounds.minY),
                width: CGFloat(result.bounds.width),
                height: CGFloat(result.bounds.height)
            )
            lastError = nil
        } catch let error as FfiLayoutError {
            lastError = .engine(error)
        } catch {
            // Task cancellation etc.
        }
    }
}

private struct EdgeEndpoints: Hashable {
    let from: UInt64
    let to: UInt64
}

extension GraphLayoutCoordinator {
    /// The graph's bounding box in its own (origin-centered) coordinate
    /// space.
    ///
    /// This now returns `engineBounds` — computed Rust-side from each
    /// node's actual width/height, not just its center — whenever it's
    /// available, which is the accurate box `GraphPlacement.offset` needs.
    /// A node-center/waypoint-only box is still computed as a fallback for
    /// the (normal) case where layout hasn't run yet, so callers keep
    /// getting *some* box back rather than `nil` for one frame.
    public var boundingBox: CGRect? {
        if let engineBounds { return engineBounds }
        guard !nodes.isEmpty else { return nil }
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        for node in nodes {
            minX = min(minX, node.x); maxX = max(maxX, node.x)
            minY = min(minY, node.y); maxY = max(maxY, node.y)
        }
        for route in routes {
            for point in route.points {
                minX = min(minX, point.x); maxX = max(maxX, point.x)
                minY = min(minY, point.y); maxY = max(maxY, point.y)
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
