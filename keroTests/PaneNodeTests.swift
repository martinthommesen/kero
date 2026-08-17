//
//  PaneNodeTests.swift
//  keroTests
//

import XCTest
@testable import kero

/// Characterization tests for the recursive pane layout tree in `Panes.swift`.
/// These pin current behavior so later refactors of the split/insert/remove
/// logic have a safety net.
final class PaneNodeTests: XCTestCase {
    @MainActor
    private func makePane() -> Pane {
        // FileTab(path:) only reads the path (guarded by `try?`); a nonexistent
        // file yields an ".unavailable" content, which is all the tree tests need.
        Pane(content: .file(FileTab(path: "/nonexistent/\(UUID().uuidString).txt")))
    }

    // MARK: - inserting

    @MainActor
    func testInsertingRightPutsNewPaneSecond() {
        let original = makePane()
        let inserted = makePane()
        let node = PaneNode.pane(original).inserting(inserted, toward: .right, beside: original.id)

        guard case .split(let split) = node else {
            return XCTFail("expected a split")
        }
        XCTAssertEqual(split.axis, .horizontal)
        guard case .pane(let first) = split.first, case .pane(let second) = split.second else {
            return XCTFail("expected two leaf panes")
        }
        XCTAssertEqual(first.id, original.id)
        XCTAssertEqual(second.id, inserted.id)
        XCTAssertEqual(node.allPanes.map(\.id), [original.id, inserted.id])
    }

    @MainActor
    func testInsertingBottomPutsNewPaneSecond() {
        let original = makePane()
        let inserted = makePane()
        let node = PaneNode.pane(original).inserting(inserted, toward: .bottom, beside: original.id)

        guard case .split(let split) = node else {
            return XCTFail("expected a split")
        }
        XCTAssertEqual(split.axis, .vertical)
        guard case .pane(let first) = split.first, case .pane(let second) = split.second else {
            return XCTFail("expected two leaf panes")
        }
        XCTAssertEqual(first.id, original.id)
        XCTAssertEqual(second.id, inserted.id)
    }

    @MainActor
    func testInsertingLeftPutsNewPaneFirst() {
        let original = makePane()
        let inserted = makePane()
        let node = PaneNode.pane(original).inserting(inserted, toward: .left, beside: original.id)

        guard case .split(let split) = node else {
            return XCTFail("expected a split")
        }
        XCTAssertEqual(split.axis, .horizontal)
        guard case .pane(let first) = split.first, case .pane(let second) = split.second else {
            return XCTFail("expected two leaf panes")
        }
        XCTAssertEqual(first.id, inserted.id)
        XCTAssertEqual(second.id, original.id)
        XCTAssertEqual(node.allPanes.map(\.id), [inserted.id, original.id])
    }

    @MainActor
    func testInsertingTopPutsNewPaneFirst() {
        let original = makePane()
        let inserted = makePane()
        let node = PaneNode.pane(original).inserting(inserted, toward: .top, beside: original.id)

        guard case .split(let split) = node else {
            return XCTFail("expected a split")
        }
        XCTAssertEqual(split.axis, .vertical)
        guard case .pane(let first) = split.first, case .pane(let second) = split.second else {
            return XCTFail("expected two leaf panes")
        }
        XCTAssertEqual(first.id, inserted.id)
        XCTAssertEqual(second.id, original.id)
    }

    // MARK: - removingPane

    @MainActor
    func testRemovingOneOfTwoSiblingsCollapsesToRemainingPane() {
        let a = makePane()
        let b = makePane()
        let node = PaneNode.pane(a).inserting(b, toward: .right, beside: a.id)

        let result = node.removingPane(a.id)
        guard case .pane(let remaining) = result.node else {
            return XCTFail("expected remaining node to collapse to a bare pane")
        }
        XCTAssertEqual(remaining.id, b.id)
        XCTAssertEqual(result.pane?.id, a.id)
    }

    @MainActor
    func testRemovingLastPaneReturnsNilNode() {
        let a = makePane()
        let node = PaneNode.pane(a)

        let result = node.removingPane(a.id)
        XCTAssertNil(result.node)
        XCTAssertEqual(result.pane?.id, a.id)
    }

    @MainActor
    func testRemovingUnknownIDLeavesTreeUnchanged() {
        let a = makePane()
        let b = makePane()
        let node = PaneNode.pane(a).inserting(b, toward: .right, beside: a.id)

        let result = node.removingPane(UUID())
        XCTAssertNil(result.pane)
        XCTAssertEqual(result.node?.allPanes.map(\.id), node.allPanes.map(\.id))
    }

    // MARK: - settingFraction / fraction

    @MainActor
    func testSettingFractionThenFractionRoundTrips() {
        let a = makePane()
        let b = makePane()
        let node = PaneNode.pane(a).inserting(b, toward: .right, beside: a.id)
        guard case .split(let split) = node else {
            return XCTFail("expected a split")
        }

        let updated = node.settingFraction(of: split.id, to: 0.75)
        XCTAssertEqual(updated.fraction(of: split.id), 0.75)
    }

    @MainActor
    func testFractionOfUnknownSplitIsNil() {
        let a = makePane()
        let b = makePane()
        let node = PaneNode.pane(a).inserting(b, toward: .right, beside: a.id)

        XCTAssertNil(node.fraction(of: UUID()))
    }

    // MARK: - equalized

    @MainActor
    func testEqualizedSetsEveryFractionToHalf() {
        let a = makePane()
        let b = makePane()
        let c = makePane()
        // Nested three-pane layout: split(split(a, b), c).
        var node = PaneNode.pane(a).inserting(b, toward: .right, beside: a.id)
        node = node.inserting(c, toward: .bottom, beside: b.id)

        let equalized = node.equalized()

        func fractions(_ n: PaneNode) -> [CGFloat] {
            switch n {
            case .pane:
                return []
            case .split(let split):
                return [split.fraction] + fractions(split.first) + fractions(split.second)
            }
        }
        XCTAssertEqual(fractions(equalized), [0.5, 0.5])
    }

    // MARK: - ancestors

    @MainActor
    func testAncestorsOfLeafTwoLevelsDeepReturnsOutermostFirst() {
        let a = makePane()
        let b = makePane()
        let c = makePane()
        // split(a, split(b, c)); b sits two levels deep under the outer split.
        var node = PaneNode.pane(a).inserting(b, toward: .right, beside: a.id)
        node = node.inserting(c, toward: .bottom, beside: b.id)

        guard case .split(let outer) = node, case .split(let inner) = outer.second else {
            return XCTFail("expected split(a, split(b, c))")
        }

        let ancestors = node.ancestors(of: b.id)
        XCTAssertEqual(ancestors?.count, 2)
        XCTAssertEqual(ancestors?[0].id, outer.id)
        XCTAssertEqual(ancestors?[1].id, inner.id)
    }

    @MainActor
    func testAncestorsOfUnknownIDIsNil() {
        let a = makePane()
        let b = makePane()
        let node = PaneNode.pane(a).inserting(b, toward: .right, beside: a.id)

        XCTAssertNil(node.ancestors(of: UUID()))
    }

    // MARK: - contains

    @MainActor
    func testContainsTrueForMemberPane() {
        let a = makePane()
        let b = makePane()
        let node = PaneNode.pane(a).inserting(b, toward: .right, beside: a.id)

        XCTAssertTrue(node.contains(a.id))
        XCTAssertTrue(node.contains(b.id))
    }

    @MainActor
    func testContainsFalseForUnknownID() {
        let a = makePane()
        let node = PaneNode.pane(a)

        XCTAssertFalse(node.contains(UUID()))
    }
}
