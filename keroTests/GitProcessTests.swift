//
//  GitProcessTests.swift
//  keroTests
//

import XCTest
@testable import kero

/// Exercises `GitProcess.run` directly, plus the `-2`/"did not respond"
/// contract that `GitStatusModel.runGit` layers on top of a timeout.
final class GitProcessTests: XCTestCase {
    func testRunsGitVersion() {
        let result = GitProcess.run(["--version"], in: "/", timeout: 10)

        XCTAssertEqual(result.status, 0)
        XCTAssertFalse(result.timedOut)
        let stdout = String(data: result.stdout, encoding: .utf8) ?? ""
        XCTAssertTrue(stdout.hasPrefix("git version"), "unexpected stdout: \(stdout)")
    }

    func testTimeoutFires() {
        // A config alias that shells out gives a deterministic hang without a
        // repo of our own.
        let started = Date()
        let result = GitProcess.run(
            ["-c", "alias.kero-slow=!sleep 5", "kero-slow"],
            in: "/",
            timeout: 0.5
        )
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(elapsed, 3, "timeout path took \(elapsed)s; expected SIGTERM within ~1s")

        let wrapped = GitStatusModel.runGit(
            ["-c", "alias.kero-slow=!sleep 5", "kero-slow"],
            in: "/",
            timeout: 0.5
        )
        XCTAssertEqual(wrapped.status, -2)
        XCTAssertTrue(
            wrapped.stderr.contains("did not respond"),
            "unexpected stderr: \(wrapped.stderr)"
        )
    }

    func testStdoutLimitCapsRetainedBytes() {
        let result = GitProcess.run(
            ["--version"], in: "/", timeout: 10, stdoutLimit: 4
        )

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout.count, 4)
    }

    func testRunFailureIsStatusMinusOne() {
        let nonexistent = "/nonexistent-dir-\(UUID().uuidString)"
        let result = GitProcess.run(["--version"], in: nonexistent, timeout: 10)

        if result.status == -1 {
            XCTAssertFalse(result.stderr.isEmpty)
        } else {
            // Process didn't throw on the missing directory; the git
            // invocation itself must still have failed.
            XCTAssertNotEqual(result.status, 0)
        }
    }
}
