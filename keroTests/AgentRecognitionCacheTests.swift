//
//  AgentRecognitionCacheTests.swift
//  keroTests
//

import XCTest
@testable import kero

/// Covers the pure recognition policy that `KeroAgentObservationState`'s
/// per-foreground-pid cache (see `AgentAutomation.swift`) memoizes, plus the
/// cache's own starting state.
final class AgentRecognitionCacheTests: XCTestCase {
    func testRecognizesClaudeByArgv0() {
        let kind = KeroAgentKind.recognize(
            executablePath: "/usr/local/bin/node",
            arguments: ["/Users/x/.claude/local/claude"]
        )
        XCTAssertEqual(kind, .claude)
    }

    func testUnrecognizedIsNil() {
        let kind = KeroAgentKind.recognize(executablePath: "/bin/zsh", arguments: ["zsh"])
        XCTAssertNil(kind)
    }

    @MainActor
    func testObservationStateStartsWithoutCache() {
        let state = KeroAgentObservationState()
        XCTAssertNil(state.recognizedPID)
        XCTAssertNil(state.recognizedKindForPID)
    }
}
