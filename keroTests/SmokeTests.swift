//
//  SmokeTests.swift
//  keroTests
//

import XCTest
@testable import kero

/// Proves the test bundle loads inside the app host and can see app symbols.
/// Real coverage lives in the per-module test files added by later plans.
final class SmokeTests: XCTestCase {
    func testAppModuleIsVisible() {
        XCTAssertNotNil(KeroAgentKind(rawValue: "claude"))
    }
}
