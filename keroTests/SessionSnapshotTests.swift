//
//  SessionSnapshotTests.swift
//  keroTests
//

import XCTest
@testable import kero

/// Characterization tests for `SessionStore.decode`'s backward-compat
/// ladder. Never calls `SessionStore.save`/`load` — those touch the real
/// developer's `UserDefaults`.
final class SessionSnapshotTests: XCTestCase {
    typealias ProjectSnapshot = SessionSnapshot.ProjectSnapshot
    typealias PaneContentSnapshot = ProjectSnapshot.PaneContentSnapshot
    typealias PaneSnapshot = ProjectSnapshot.PaneSnapshot
    typealias LayoutSnapshot = ProjectSnapshot.LayoutSnapshot
    typealias TabSnapshot = ProjectSnapshot.TabSnapshot

    // MARK: - Round-trip through the current multi-window format

    func testRoundTripsCurrentFormat() throws {
        let sessionPane = PaneSnapshot(
            content: .session(workingDirectory: "/tmp/project"),
            weight: 1,
            historyKey: "history-123"
        )
        let filePane = PaneSnapshot(
            content: .file(path: "/tmp/project/main.swift", editorState: EditorState(
                selectionLocation: 5, selectionLength: 2, scrollX: 0, scrollY: 40
            )),
            weight: 1,
            historyKey: nil
        )
        let layout = LayoutSnapshot.split(
            axis: .horizontal, fraction: 0.5,
            first: .pane(sessionPane), second: .pane(filePane)
        )
        let tab = TabSnapshot(
            layout: layout, focusedPaneIndex: 1,
            customName: "My Tab", contextSessionIndex: 0
        )
        let project = ProjectSnapshot(
            customName: "My Project", customDirectory: "/tmp/project",
            tabs: [tab], selectedTabIndex: 0
        )
        let snapshot = SessionSnapshot(
            projects: [project], selectedProjectIndex: 0,
            isLeftSidebarVisible: true, isRightPanelVisible: false,
            rightPanelTab: .git
        )

        let data = try JSONEncoder().encode(AppSnapshot(windows: [snapshot]))
        let decoded = SessionStore.decode(data)

        XCTAssertEqual(decoded.count, 1)
        let decodedSnapshot = decoded[0]
        XCTAssertEqual(decodedSnapshot.selectedProjectIndex, 0)
        XCTAssertEqual(decodedSnapshot.isLeftSidebarVisible, true)
        XCTAssertEqual(decodedSnapshot.isRightPanelVisible, false)
        XCTAssertEqual(decodedSnapshot.rightPanelTab, .git)

        XCTAssertEqual(decodedSnapshot.projects.count, 1)
        let decodedProject = decodedSnapshot.projects[0]
        XCTAssertEqual(decodedProject.customName, "My Project")
        XCTAssertEqual(decodedProject.customDirectory, "/tmp/project")
        XCTAssertEqual(decodedProject.selectedTabIndex, 0)

        XCTAssertEqual(decodedProject.tabs.count, 1)
        let decodedTab = decodedProject.tabs[0]
        XCTAssertEqual(decodedTab.focusedPaneIndex, 1)
        XCTAssertEqual(decodedTab.customName, "My Tab")
        XCTAssertEqual(decodedTab.contextSessionIndex, 0)

        guard case .split(let axis, let fraction, let first, let second) = decodedTab.layout else {
            return XCTFail("expected a split layout")
        }
        XCTAssertEqual(axis, .horizontal)
        XCTAssertEqual(fraction, 0.5)
        guard case .pane(let decodedSessionPane) = first,
              case .session(let workingDirectory) = decodedSessionPane.content else {
            return XCTFail("expected first leaf to be a session pane")
        }
        XCTAssertEqual(workingDirectory, "/tmp/project")
        XCTAssertEqual(decodedSessionPane.historyKey, "history-123")

        guard case .pane(let decodedFilePane) = second,
              case .file(let path, let editorState) = decodedFilePane.content else {
            return XCTFail("expected second leaf to be a file pane")
        }
        XCTAssertEqual(path, "/tmp/project/main.swift")
        XCTAssertEqual(editorState?.selectionLocation, 5)
        XCTAssertEqual(editorState?.selectionLength, 2)
        XCTAssertEqual(editorState?.scrollX, 0)
        XCTAssertEqual(editorState?.scrollY, 40)
        XCTAssertNil(decodedFilePane.historyKey)
    }

    // MARK: - Legacy single-window format

    func testDecodesLegacySingleWindowSnapshot() throws {
        let pane = PaneSnapshot(
            content: .browser(url: "https://example.com"), weight: 1, historyKey: nil
        )
        let tab = TabSnapshot(layout: .pane(pane), focusedPaneIndex: 0)
        let project = ProjectSnapshot(
            customName: nil, customDirectory: nil, tabs: [tab], selectedTabIndex: nil
        )
        let snapshot = SessionSnapshot(
            projects: [project], selectedProjectIndex: nil,
            isLeftSidebarVisible: nil, isRightPanelVisible: nil, rightPanelTab: nil
        )

        // Not wrapped in AppSnapshot — the pre-multi-window shape.
        let data = try JSONEncoder().encode(snapshot)
        let decoded = SessionStore.decode(data)

        XCTAssertEqual(decoded.count, 1)
        guard case .pane(let decodedPane) = decoded[0].projects[0].tabs[0].layout,
              case .browser(let url) = decodedPane.content else {
            return XCTFail("expected a single browser pane")
        }
        XCTAssertEqual(url, "https://example.com")
    }

    // MARK: - Missing optionals decode to nil

    func testTabSnapshotWithoutCustomNameOrContextSessionIndexDecodesToNil() throws {
        let json = """
        {
            "layout": {"pane": {"_0": {"content": {"file": {"path": "/tmp/a.txt"}}, "weight": 1}}},
            "focusedPaneIndex": 0
        }
        """
        let tab = try JSONDecoder().decode(TabSnapshot.self, from: Data(json.utf8))

        XCTAssertNil(tab.customName)
        XCTAssertNil(tab.contextSessionIndex)
        XCTAssertEqual(tab.focusedPaneIndex, 0)
        guard case .pane(let pane) = tab.layout, case .file(let path, let editorState) = pane.content else {
            return XCTFail("expected a file pane")
        }
        XCTAssertEqual(path, "/tmp/a.txt")
        XCTAssertNil(editorState)
    }

    func testPaneSnapshotWithoutHistoryKeyDecodesToNil() throws {
        let json = """
        {"content": {"session": {"workingDirectory": "/tmp"}}, "weight": 1}
        """
        let pane = try JSONDecoder().decode(PaneSnapshot.self, from: Data(json.utf8))

        XCTAssertNil(pane.historyKey)
        guard case .session(let workingDirectory) = pane.content else {
            return XCTFail("expected a session pane")
        }
        XCTAssertEqual(workingDirectory, "/tmp")
    }

    // MARK: - Garbage input

    func testDecodeGarbageDataReturnsEmptyArray() {
        XCTAssertTrue(SessionStore.decode(Data("nope".utf8)).isEmpty)
    }

    // MARK: - Legacy pre-split layout shapes (TabSnapshot.init(from:))

    /// The original pre-split shape: a tab was a bare `PaneContentSnapshot`,
    /// wrapped into a one-pane layout on decode.
    func testDecodesOriginalPreSplitSingleContentShape() throws {
        let json = """
        {"file": {"path": "/tmp/legacy.txt"}}
        """
        let tab = try JSONDecoder().decode(TabSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(tab.focusedPaneIndex, 0)
        XCTAssertNil(tab.customName)
        XCTAssertNil(tab.contextSessionIndex)
        guard case .pane(let pane) = tab.layout, case .file(let path, _) = pane.content else {
            return XCTFail("expected a single-pane file layout")
        }
        XCTAssertEqual(path, "/tmp/legacy.txt")
    }

    /// The former column/row grid shape: a two-column, one-pane-each layout
    /// converts to a horizontal split, and focusedColumn/focusedRow map to
    /// a flattened focusedPaneIndex.
    func testDecodesFormerColumnRowShape() throws {
        let json = """
        {
            "columns": [
                {
                    "panes": [
                        {"content": {"session": {"workingDirectory": "/tmp/left"}}, "weight": 1}
                    ],
                    "weight": 1
                },
                {
                    "panes": [
                        {"content": {"session": {"workingDirectory": "/tmp/right"}}, "weight": 1}
                    ],
                    "weight": 1
                }
            ],
            "focusedColumn": 1,
            "focusedRow": 0
        }
        """
        let tab = try JSONDecoder().decode(TabSnapshot.self, from: Data(json.utf8))

        // One pane per column before the focused column, so the flattened
        // index for column 1 / row 0 is 1.
        XCTAssertEqual(tab.focusedPaneIndex, 1)
        guard case .split(let axis, _, let first, let second) = tab.layout else {
            return XCTFail("expected a horizontal split of the two columns")
        }
        XCTAssertEqual(axis, .horizontal)
        guard case .pane(let leftPane) = first, case .session(let leftDir) = leftPane.content else {
            return XCTFail("expected left column to be a session pane")
        }
        XCTAssertEqual(leftDir, "/tmp/left")
        guard case .pane(let rightPane) = second, case .session(let rightDir) = rightPane.content else {
            return XCTFail("expected right column to be a session pane")
        }
        XCTAssertEqual(rightDir, "/tmp/right")
    }
}
