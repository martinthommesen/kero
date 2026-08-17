//
//  KeroJSONValueTests.swift
//  keroTests
//

import XCTest
@testable import kero

/// Characterization tests for `KeroJSONValue`'s custom decode, which probes
/// nil -> Bool -> Double -> String -> object -> array in that order, and for
/// the wire structs that embed it.
final class KeroJSONValueTests: XCTestCase {
    private func decode(_ json: String) throws -> KeroJSONValue {
        try JSONDecoder().decode(KeroJSONValue.self, from: Data(json.utf8))
    }

    // MARK: - Round-trip per case

    func testRoundTripsEachCase() throws {
        let values: [KeroJSONValue] = [
            .string("x"),
            .number(1.5),
            .bool(true),
            .null,
            .array([.string("a"), .number(2)]),
            .object(["k": .bool(false)]),
        ]
        for value in values {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(KeroJSONValue.self, from: data)
            XCTAssertEqual(decoded, value)
        }
    }

    // MARK: - Probe order pins

    func testNumberOneDecodesAsNumberNotBool() throws {
        XCTAssertEqual(try decode("1"), .number(1))
    }

    func testNumberZeroDecodesAsNumberNotBool() throws {
        XCTAssertEqual(try decode("0"), .number(0))
    }

    func testTrueDecodesAsBool() throws {
        XCTAssertEqual(try decode("true"), .bool(true))
    }

    func testQuotedTrueDecodesAsString() throws {
        XCTAssertEqual(try decode("\"true\""), .string("true"))
    }

    func testQuotedOneDecodesAsString() throws {
        XCTAssertEqual(try decode("\"1\""), .string("1"))
    }

    // MARK: - Nested structures

    func testNestedObjectWithNullValue() throws {
        XCTAssertEqual(try decode(#"{"k": null}"#), .object(["k": .null]))
    }

    // MARK: - Wire structs

    func testKeroAutomationRequestRoundTrips() throws {
        let request = KeroAutomationRequest(
            version: 1, id: "req-1", method: "read", token: "tok",
            terminalID: "term-1", params: ["lines": .number(40), "flag": .bool(true)]
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(KeroAutomationRequest.self, from: data)

        XCTAssertEqual(decoded.version, request.version)
        XCTAssertEqual(decoded.id, request.id)
        XCTAssertEqual(decoded.method, request.method)
        XCTAssertEqual(decoded.token, request.token)
        XCTAssertEqual(decoded.terminalID, request.terminalID)
        XCTAssertEqual(decoded.params, request.params)
    }

    func testKeroAutomationResponseRoundTripsSuccessAndFailure() throws {
        let success = KeroAutomationResponse.success(id: "1", result: .string("ok"))
        let successData = try JSONEncoder().encode(success)
        let decodedSuccess = try JSONDecoder().decode(KeroAutomationResponse.self, from: successData)
        XCTAssertEqual(decodedSuccess.ok, true)
        XCTAssertEqual(decodedSuccess.result, .string("ok"))
        XCTAssertNil(decodedSuccess.error)

        let failure = KeroAutomationResponse.failure(id: "2", code: "bad", message: "nope")
        let failureData = try JSONEncoder().encode(failure)
        let decodedFailure = try JSONDecoder().decode(KeroAutomationResponse.self, from: failureData)
        XCTAssertEqual(decodedFailure.ok, false)
        XCTAssertNil(decodedFailure.result)
        XCTAssertEqual(decodedFailure.error?.code, "bad")
        XCTAssertEqual(decodedFailure.error?.message, "nope")
    }
}
