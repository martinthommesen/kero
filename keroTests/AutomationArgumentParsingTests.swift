//
//  AutomationArgumentParsingTests.swift
//  keroTests
//

import XCTest
@testable import kero

/// Characterization tests for the CLI's small hand-rolled argument parsers.
final class AutomationArgumentParsingTests: XCTestCase {
    typealias CommandLine = KeroAutomationCommandLine

    // MARK: - parsePaneOnly

    func testParsePaneOnlyWithPaneFlag() throws {
        let paneID = try CommandLine.parsePaneOnly(["--pane", "abc"], command: "x")
        XCTAssertEqual(paneID, "abc")
    }

    func testParsePaneOnlyWithCurrentFlag() throws {
        let paneID = try CommandLine.parsePaneOnly(["--current"], command: "x")
        XCTAssertNil(paneID)
    }

    func testParsePaneOnlyWithNoArguments() throws {
        let paneID = try CommandLine.parsePaneOnly([], command: "x")
        XCTAssertNil(paneID)
    }

    func testParsePaneOnlyWithUnknownOptionThrows() {
        XCTAssertThrowsError(try CommandLine.parsePaneOnly(["--bogus"], command: "x"))
    }

    func testParsePaneOnlyWithMissingValueThrows() {
        XCTAssertThrowsError(try CommandLine.parsePaneOnly(["--pane"], command: "x"))
    }

    // MARK: - parseReadOptions

    func testParseReadOptionsSetsFields() throws {
        let options = try CommandLine.parseReadOptions(
            ["--lines", "40", "--columns", "120"], command: "read"
        )
        XCTAssertNil(options.paneID)
        XCTAssertEqual(options.lines, 40)
        XCTAssertEqual(options.columns, 120)
    }

    func testParseReadOptionsWithNonNumericLinesThrows() {
        XCTAssertThrowsError(
            try CommandLine.parseReadOptions(["--lines", "abc"], command: "read")
        )
    }

    // MARK: - parseAgentTarget

    func testParseAgentTargetWithPaneFlag() throws {
        let target = try CommandLine.parseAgentTarget(["--pane", "p"], command: "x")
        XCTAssertEqual(target.paneID, "p")
        XCTAssertNil(target.alias)
    }

    func testParseAgentTargetWithCurrentFlagDoesNotThrow() throws {
        let target = try CommandLine.parseAgentTarget(["--current"], command: "x")
        XCTAssertNil(target.paneID)
        XCTAssertNil(target.alias)
    }

    func testParseAgentTargetWithPositionalAlias() throws {
        let target = try CommandLine.parseAgentTarget(["alias"], command: "x")
        XCTAssertEqual(target.alias, "alias")
        XCTAssertNil(target.paneID)
    }

    func testParseAgentTargetWithPaneAndCurrentThrowsChooseExactlyOne() {
        XCTAssertThrowsError(
            try CommandLine.parseAgentTarget(["--pane", "p", "--current"], command: "x")
        ) { error in
            XCTAssertEqual(
                (error as? CLIError)?.description,
                "Choose exactly one agent alias, --pane, or --current."
            )
        }
    }

    func testParseAgentTargetWithAliasAndPaneThrows() {
        XCTAssertThrowsError(
            try CommandLine.parseAgentTarget(["alias", "--pane", "p"], command: "x")
        )
    }
}
