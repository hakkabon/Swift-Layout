//
//  GraphFlattening.swift
//  Test-FFI
//
//  Created by Ulf Akerstedt-Inoue on 2026/08/12.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation
import SwiftLayout

/// Something that can turn a domain-specific graph into the flat
/// `[FfiNode]` / `[FfiEdge]` shape the layout engine's FFI call expects,
/// while remembering how to map each FFI id back to the original node.
///
/// Implement one conformance per graph kind (syntax tree, SPPF, GSS,
/// FSA/DFA) — the traversal differs, but the output shape doesn't.
public protocol GraphFlattening {
    associatedtype Node: AnyObject

    /// Returns the flattened FFI input, plus a lookup from the FFI id
    /// assigned to each node back to the original domain node — the
    /// reconstruction step needs this to rejoin positions to nodes.
    func flatten() -> (nodes: [FfiNode], edges: [FfiEdge], lookup: [UInt64: Node])

    /// Returns the presentation text associated with an FFI edge, if any.
    ///
    /// The Rust engine only needs the label's dimensions for placement. Keeping
    /// the text here lets the Swift wrapper reattach domain content to the
    /// positioned route without exposing it across the FFI boundary.
    func label(for edge: FfiEdge) -> String?
}

public extension GraphFlattening {
    /// Unlabelled graphs need no extra implementation.
    func label(for edge: FfiEdge) -> String? { nil }
}
