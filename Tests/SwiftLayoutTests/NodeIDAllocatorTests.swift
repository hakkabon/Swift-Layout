//
//  NodeIDAllocatorTests.swift
//  SwiftLayoutTests
//

import XCTest
import SwiftLayout

/// `NodeIDAllocator` hands out a stable `UInt64` per object for the
/// lifetime of one `flatten()` call — but every `GraphFlattening`
/// conformance in Sample-App creates a *fresh* allocator on every call
/// (see `FSAFlattener`, `SyntaxTreeFlattener`, etc.). What makes id
/// assignment stable across repeated `flatten()` calls on an unchanged
/// domain graph isn't the allocator remembering anything — it's that
/// deterministic traversal order visits the same objects in the same
/// order every time, so a fresh allocator reproduces the same assignment.
///
/// That's the property `GraphLayoutCoordinator.nodes`' `Identifiable`
/// conformance (and therefore SwiftUI's ability to animate a relayout
/// instead of tearing down and recreating every node view) quietly
/// depends on. These tests pin it down directly, at the allocator level;
/// `GraphFlatteningIdentityTests` does the same thing one layer up,
/// against something that actually looks like a `GraphFlattening`
/// conformance.
final class NodeIDAllocatorTests: XCTestCase {

    /// Stand-in for a real domain node (`FSAState`, an SPPF/GSS node,
    /// whatever) — all that matters for the allocator is that it's a
    /// class, i.e. has real reference identity.
    private final class Node {}

    func testSameObjectAlwaysGetsTheSameID() {
        let allocator = NodeIDAllocator()
        let node = Node()
        XCTAssertEqual(allocator.id(for: node), allocator.id(for: node))
    }

    func testDistinctObjectsGetDistinctIDs() {
        let allocator = NodeIDAllocator()
        let a = Node()
        let b = Node()
        XCTAssertNotEqual(allocator.id(for: a), allocator.id(for: b))
    }

    func testIDsAreDenseStartingAtZeroInDiscoveryOrder() {
        let allocator = NodeIDAllocator()
        let nodes = (0..<5).map { _ in Node() }
        let ids = nodes.map { allocator.id(for: $0) }
        XCTAssertEqual(
            ids, [0, 1, 2, 3, 4],
            "ids should be dense small integers assigned in discovery order, starting at 0 — that's what makes them usable as FFI node ids"
        )
    }

    /// The property that actually matters downstream: two independent
    /// allocators, each visiting the same objects in the same order, must
    /// agree on every id — exactly the "fresh allocator per flatten()
    /// call" situation every real conformance is in.
    func testTwoFreshAllocatorsAgreeGivenTheSameTraversalOrder() {
        let nodes = (0..<8).map { _ in Node() }

        let first = NodeIDAllocator()
        let firstIDs = nodes.map { first.id(for: $0) }

        let second = NodeIDAllocator()
        let secondIDs = nodes.map { second.id(for: $0) }

        XCTAssertEqual(
            firstIDs, secondIDs,
            "the same objects visited in the same order must get the same ids across separate allocator instances"
        )
    }

    /// The flip side, stated explicitly: id stability is a property of
    /// *deterministic traversal order*, not something the allocator
    /// guarantees on its own. If a `GraphFlattening` conformance ever
    /// switched from iterating an array to iterating a `Set` (or a
    /// `Dictionary`'s keys) to discover nodes, this is the property that
    /// would quietly stop holding — worth having this test spell out why,
    /// rather than leaving it as an unstated assumption.
    func testDifferentTraversalOrderCanProduceDifferentIDs() {
        let a = Node()
        let b = Node()

        let forward = NodeIDAllocator()
        let forwardA = forward.id(for: a)
        let forwardB = forward.id(for: b)

        let reversed = NodeIDAllocator()
        _ = reversed.id(for: b)
        let reversedA = reversed.id(for: a)

        XCTAssertNotEqual(
            forwardA, reversedA,
            "visiting the same two objects in a different order assigns different ids"
        )
        XCTAssertEqual(forwardA, 0)
        XCTAssertEqual(forwardB, 1)
    }
}
