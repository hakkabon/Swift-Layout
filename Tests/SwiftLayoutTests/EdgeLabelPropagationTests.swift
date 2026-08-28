import XCTest
@testable import SwiftLayout

private final class LabelledNode {}

private struct LabelledEdgeFlattener: GraphFlattening {
    let source = LabelledNode()
    let target = LabelledNode()

    func flatten() -> (nodes: [FfiNode], edges: [FfiEdge], lookup: [UInt64: LabelledNode]) {
        (
            nodes: [
                FfiNode(id: 0, width: 40, height: 20, rankHint: nil, rankConstraint: .preferred),
                FfiNode(id: 1, width: 40, height: 20, rankHint: nil, rankConstraint: .preferred),
            ],
            edges: [FfiEdge(id: 0, from: 0, to: 1, labelWidth: 36, labelHeight: 14)],
            lookup: [0: source, 1: target]
        )
    }

    func label(for edge: FfiEdge) -> String? {
        edge.from == 0 && edge.to == 1 ? "weight 7" : nil
    }
}

final class EdgeLabelPropagationTests: XCTestCase {
    @MainActor
    func testCoordinatorReattachesLabelTextAndPositionToRoute() async {
        let coordinator = GraphLayoutCoordinator<LabelledNode>()
        await coordinator.relayout(
            LabelledEdgeFlattener(),
            config: FfiConfig(
                hGap: 24,
                vGap: 48,
                relaxPasses: 4,
                sweeps: 4,
                algorithm: .brandesKopf,
                routing: .straight,
                direction: .topToBottom
            )
        )

        XCTAssertNil(coordinator.lastError)
        XCTAssertEqual(coordinator.routes.count, 1)
        XCTAssertEqual(coordinator.routes.first?.label, "weight 7")
        XCTAssertNotNil(coordinator.routes.first?.labelPosition)
    }
}
