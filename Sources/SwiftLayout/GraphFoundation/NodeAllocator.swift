//
//  NodeAllocator.swift
//  Test-FFI
//
//  Created by Ulf Akerstedt-Inoue on 2026/08/12.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation

/// Provide stable FFI ids for arbitrary domain node types
///
/// The FFI layer identifies nodes with an opaque `UInt64` (see `FfiNode`).
/// Domain graphs (syntax tree nodes, SPPF nodes, GSS nodes, FSA states)
/// are reference types with their own identity, not small dense integers,
/// so this allocator hands out a stable id per object for the lifetime of
/// one flatten-call.
public final class NodeIDAllocator {
    private var ids: [ObjectIdentifier: UInt64] = [:]
    private var next: UInt64 = 0

    // public initializer
    public init() {}

    public func id(for object: AnyObject) -> UInt64 {
        let key = ObjectIdentifier(object)
        if let existing = ids[key] { return existing }
        let assigned = next
        next += 1
        ids[key] = assigned
        return assigned
    }
}
