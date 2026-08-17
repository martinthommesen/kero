//
//  TOMLTests.swift
//  keroTests
//

import XCTest
@testable import kero

/// Characterization tests for the hand-rolled TOML reader/writer that backs
/// `config.toml`. Fixtures are written to temporary files since `parse(at:)`
/// takes a `URL`.
final class TOMLTests: XCTestCase {
    private var fixtureURL: URL!

    override func setUp() {
        super.setUp()
        fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TOMLTests-\(UUID().uuidString).toml")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fixtureURL)
        fixtureURL = nil
        super.tearDown()
    }

    private func parse(_ contents: String) -> [String: TOML.Value]? {
        try? contents.write(to: fixtureURL, atomically: true, encoding: .utf8)
        return TOML.parse(at: fixtureURL)
    }

    // MARK: - Basic scalar types

    func testParsesNumberStringAndBoolValues() {
        let table = parse("""
        font-size = 14
        theme = "dark"
        terminal.font-thicken = true
        """)

        XCTAssertEqual(table?["font-size"]?.double, 14)
        XCTAssertEqual(table?["theme"]?.string, "dark")
        XCTAssertEqual(table?["terminal.font-thicken"]?.bool, true)
    }

    // MARK: - Table headers

    func testTableHeaderFlattensKeysWithDot() {
        let table = parse("""
        [terminal]
        backend = "alacritty"
        """)

        XCTAssertEqual(table?["terminal.backend"]?.string, "alacritty")
    }

    // MARK: - Comments

    func testFullLineCommentIsSkipped() {
        let table = parse("""
        # this is a comment
        value = 1
        """)

        XCTAssertEqual(table?.count, 1)
        XCTAssertEqual(table?["value"]?.double, 1)
    }

    func testTrailingCommentAfterUnquotedValueIsStripped() {
        let table = parse("retries = 3 # comment")

        XCTAssertEqual(table?["retries"]?.double, 3)
    }

    // MARK: - Escapes inside quoted strings

    func testQuotedStringEscapes() {
        // \" -> " and \\ -> \, per parseValue's escape handling.
        let table = parse(#"name = "a \"quoted\" \\ path""#)

        XCTAssertEqual(table?["name"]?.string, "a \"quoted\" \\ path")
    }

    // MARK: - Number formats

    func testNegativeAndFloatNumbers() {
        let table = parse("""
        neg = -1
        flt = 1.5
        """)

        XCTAssertEqual(table?["neg"]?.double, -1)
        XCTAssertEqual(table?["flt"]?.double, 1.5)
    }

    // MARK: - quote(_:) round-trip

    func testQuoteThenParseRoundTripsSpecialCharacters() {
        let original = "a \"quoted\" \\ value"
        let quoted = TOML.quote(original)
        let table = parse("key = \(quoted)")

        XCTAssertEqual(table?["key"]?.string, original)
    }

    // MARK: - number(_:) formatting

    func testNumberFormatsWholeNumbersWithoutDecimal() {
        XCTAssertEqual(TOML.number(14.0), "14")
    }

    func testNumberFormatsFractionalValues() {
        XCTAssertEqual(TOML.number(1.5), "1.5")
    }

    // MARK: - Malformed lines

    func testMalformedLineWithoutEqualsIsSkippedOthersStillParsed() {
        let table = parse("""
        no-equals-sign
        key = 1
        """)

        XCTAssertNil(table?["no-equals-sign"])
        XCTAssertEqual(table?["key"]?.double, 1)
        XCTAssertEqual(table?.count, 1)
    }
}
