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

    /// Mirrors the poll's cache-hit condition: a positive kind for the current
    /// foreground pid is reused; clearing both fields (shell takeover) drops it.
    @MainActor
    func testPositiveCacheHitUntilClearedOnShellTakeover() {
        let state = KeroAgentObservationState()
        let foreground: pid_t = 4242
        state.recognizedPID = foreground
        state.recognizedKindForPID = .claude

        let hit =
            state.recognizedPID == foreground
            ? state.recognizedKindForPID
            : nil
        XCTAssertEqual(hit, .claude)

        // Shell takeover clears both fields (see refreshAutomationAgentState).
        state.recognizedPID = nil
        state.recognizedKindForPID = nil
        let afterClear =
            state.recognizedPID == foreground
            ? state.recognizedKindForPID
            : nil
        XCTAssertNil(afterClear)
    }
}
