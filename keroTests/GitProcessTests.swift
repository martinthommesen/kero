//
//  GitProcessTests.swift
//  keroTests
//

import XCTest
@testable import kero

/// Exercises `GitProcess.run` directly, plus the `-2`/"did not respond"
/// contract that `GitStatusModel.runGit` layers on top of a timeout.
final class GitProcessTests: XCTestCase {
    private func makeTempRepo() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitProcessTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: dir)
        }
        let initResult = GitProcess.run(["init"], in: dir.path, timeout: 10)
        XCTAssertEqual(initResult.status, 0, "git init failed to set up the fixture repo")
        return dir.path
    }

    func testRunsGitVersion() {
        let result = GitProcess.run(["--version"], in: NSTemporaryDirectory(), timeout: 10)

        XCTAssertEqual(result.status, 0)
        XCTAssertFalse(result.timedOut)
        let stdout = String(data: result.stdout, encoding: .utf8) ?? ""
        XCTAssertTrue(stdout.contains("git version"), "unexpected stdout: \(stdout)")
    }

    func testTimeoutFires() throws {
        let repo = try makeTempRepo()
        let alias = GitProcess.run(
            ["config", "alias.kero-slow", "!sleep 5"], in: repo, timeout: 10
        )
        XCTAssertEqual(alias.status, 0, "failed to configure the slow alias")

        let result = GitProcess.run(["kero-slow"], in: repo, timeout: 0.5)
        XCTAssertTrue(result.timedOut)

        let wrapped = GitStatusModel.runGit(["kero-slow"], in: repo, timeout: 0.5)
        XCTAssertEqual(wrapped.status, -2)
        XCTAssertTrue(
            wrapped.stderr.contains("did not respond"),
            "unexpected stderr: \(wrapped.stderr)"
        )
    }

    func testStdoutLimitCapsRetainedBytes() {
        let result = GitProcess.run(
            ["--version"], in: NSTemporaryDirectory(), timeout: 10, stdoutLimit: 4
        )

        XCTAssertEqual(result.stdout.count, 4)
    }

    func testRunFailureIsStatusMinusOne() {
        let nonexistent = NSTemporaryDirectory() + "GitProcessTests-missing-\(UUID().uuidString)"
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
