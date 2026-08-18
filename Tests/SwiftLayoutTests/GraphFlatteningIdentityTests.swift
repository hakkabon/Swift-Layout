//
//  GraphFlatteningIdentityTests.swift
//  SwiftLayoutTests
//

import XCTest
import SwiftLayout

/// A minimal `GraphFlattening` conformance over a plain reference-type
/// tree — small enough to keep here rather than depending on any of
/// Sample-App's real flatteners, but structured the same way they are:
/// fresh `NodeIDAllocator`, deterministic array-order traversal.
private final class TreeNode {
    let name: String
    let children: [TreeNode]
    init(_ name: String, children: [TreeNode] = []) {
        self.name = name
        self.children = children
    }
}

private struct TreeFlattener: GraphFlattening {
    let root: TreeNode

    func flatten() -> (nodes: [FfiNode], edges: [FfiEdge], lookup: [UInt64: TreeNode]) {
        let ids = NodeIDAllocator()
        var nodes: [FfiNode] = []
        var edges: [FfiEdge] = []
        var lookup: [UInt64: TreeNode] = [:]

        func visit(_ node: TreeNode) {
            let id = ids.id(for: node)
            nodes.append(FfiNode(id: id, width: 40, height: 20))
            lookup[id] = node
            for child in node.children {
                edges.append(FfiEdge(from: id, to: ids.id(for: child), labelWidth: nil, labelHeight: nil))
                visit(child)
            }
        }
        visit(root)
        return (nodes, edges, lookup)
    }
}

/// Like `TreeFlattener`, but over a small DAG with a genuinely shared
/// node reachable via two different parents — the shape an SPPF or GSS
/// flattener actually produces, as opposed to a plain tree. A `visited`
/// set is needed here to avoid infinite recursion / duplicate edges on
/// re-visiting `merge`; that's exactly the kind of code most likely to
/// accidentally introduce nondeterministic order (e.g. iterating the
/// `visited` set instead of the discovery array) in a real conformance.
private struct DiamondDAGFlattener: GraphFlattening {
    let root: TreeNode

    func flatten() -> (nodes: [FfiNode], edges: [FfiEdge], lookup: [UInt64: TreeNode]) {
        let ids = NodeIDAllocator()
        var nodes: [FfiNode] = []
        var edges: [FfiEdge] = []
        var lookup: [UInt64: TreeNode] = [:]
        var visited: Set<ObjectIdentifier> = []

        func visit(_ node: TreeNode) {
            let id = ids.id(for: node)
            if visited.insert(ObjectIdentifier(node)).inserted {
                nodes.append(FfiNode(id: id, width: 40, height: 20))
                lookup[id] = node
            }
            for child in node.children {
                edges.append(FfiEdge(from: id, to: ids.id(for: child), labelWidth: nil, labelHeight: nil))
                if !visited.contains(ObjectIdentifier(child)) {
                    visit(child)
                }
            }
        }
        visit(root)
        return (nodes, edges, lookup)
    }
}

private func id(of node: TreeNode, in lookup: [UInt64: TreeNode]) -> UInt64? {
    lookup.first(where: { $0.value === node })?.key
}

final class GraphFlatteningIdentityTests: XCTestCase {

    /// The regression this is actually guarding: flatten the exact same
    /// domain graph twice (as `GraphLayoutCoordinator.relayout` does on
    /// every relayout — switching the algorithm picker, resizing the
    /// canvas, anything that re-triggers layout without the underlying
    /// graph changing) and every node must come back with the same id
    /// both times, so `PositionedNode`'s `Identifiable` conformance lets
    /// SwiftUI track continuity instead of recreating every view.
    func testFlatteningTheSameTreeTwiceAssignsTheSameIDs() {
        let leaf1 = TreeNode("leaf1")
        let leaf2 = TreeNode("leaf2")
        let root = TreeNode("root", children: [leaf1, leaf2])
        let flattener = TreeFlattener(root: root)

        let first = flattener.flatten()
        let second = flattener.flatten()

        XCTAssertEqual(first.nodes.count, second.nodes.count)
        XCTAssertEqual(first.edges.count, second.edges.count)

        for node in [root, leaf1, leaf2] {
            let firstID = id(of: node, in: first.lookup)
            let secondID = id(of: node, in: second.lookup)
            XCTAssertNotNil(firstID, "\(node.name) should be present in the first flatten's lookup")
            XCTAssertEqual(firstID, secondID, "\(node.name) should get the same FFI id on both flatten() calls")
        }
    }

    /// Same property, over a DAG with a shared node instead of a tree —
    /// the shape that actually matters, since `SPPFFlattener` and
    /// `GSSFlattener` are DAG flatteners, not tree flatteners, and the
    /// `visited`-set bookkeeping a DAG traversal needs is exactly the kind
    /// of code most likely to accidentally introduce nondeterminism.
    func testFlatteningTheSameDAGTwiceAssignsTheSameIDs() {
        let merge = TreeNode("merge")
        let a = TreeNode("a", children: [merge])
        let b = TreeNode("b", children: [merge])
        let root = TreeNode("root", children: [a, b])
        let flattener = DiamondDAGFlattener(root: root)

        let first = flattener.flatten()
        let second = flattener.flatten()

        // 4 distinct nodes (root, a, b, merge — merge counted once despite
        // two parents), 4 edges (root->a, root->b, a->merge, b->merge).
        XCTAssertEqual(first.nodes.count, 4)
        XCTAssertEqual(first.edges.count, 4)
        XCTAssertEqual(first.nodes.count, second.nodes.count)
        XCTAssertEqual(first.edges.count, second.edges.count)

        for node in [root, a, b, merge] {
            let firstID = id(of: node, in: first.lookup)
            let secondID = id(of: node, in: second.lookup)
            XCTAssertNotNil(firstID, "\(node.name) should be present in the first flatten's lookup")
            XCTAssertEqual(firstID, secondID, "\(node.name) should get the same FFI id on both flatten() calls")
        }
    }
}
