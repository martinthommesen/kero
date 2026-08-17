//
//  GitStatusParsingTests.swift
//  keroTests
//

import XCTest
@testable import kero

/// Characterization tests for `GitStatusModel`'s pure parsers: porcelain v2
/// status, numstat line counts, and the `--name-status -z` recent-commits
/// format. Fixtures use explicit NUL/US/RS separators to pin the exact
/// tokenization the parsers rely on.
final class GitStatusParsingTests: XCTestCase {
    typealias Entry = GitStatusModel.Entry
    typealias StatusResult = GitStatusModel.StatusResult

    // MARK: - parseStatus: headers

    func testParseStatusHeaderFields() {
        let output = "# branch.oid abc\0# branch.head main\0# branch.upstream origin/main\0# branch.ab +2 -1\0"
        let result = GitStatusModel.parseStatus(output)

        XCTAssertEqual(result.branch, "main")
        XCTAssertEqual(result.headOID, "abc")
        XCTAssertTrue(result.hasHead)
        XCTAssertEqual(result.upstream, "origin/main")
        XCTAssertEqual(result.ahead, 2)
        XCTAssertEqual(result.behind, 1)
        XCTAssertTrue(result.entries.isEmpty)
    }

    func testParseStatusInitialCommitHasNoHead() {
        let output = "# branch.oid (initial)\0"
        let result = GitStatusModel.parseStatus(output)

        XCTAssertFalse(result.hasHead)
        XCTAssertNil(result.headOID)
    }

    func testParseStatusDetachedHeadBranchName() {
        let output = "# branch.head (detached)\0"
        let result = GitStatusModel.parseStatus(output)

        XCTAssertEqual(result.branch, "detached HEAD")
    }

    // MARK: - parseStatus: entries

    func testParseStatusOrdinaryEntryWithSpacesInPath() {
        let output = "1 M. N... 100644 100644 100644 h h path with spaces.txt\0"
        let result = GitStatusModel.parseStatus(output)

        XCTAssertEqual(result.entries.count, 1)
        let entry = result.entries[0]
        XCTAssertEqual(entry.staged, "M")
        XCTAssertEqual(entry.unstaged, ".")
        XCTAssertEqual(entry.path, "path with spaces.txt")
        XCTAssertFalse(entry.isConflict)
        XCTAssertNil(entry.origPath)
    }

    func testParseStatusRenameEntryCarriesOriginalPath() {
        let output = "2 R. N... 100644 100644 100644 h h R100 new.txt\0old.txt\0"
        let result = GitStatusModel.parseStatus(output)

        XCTAssertEqual(result.entries.count, 1)
        let entry = result.entries[0]
        XCTAssertEqual(entry.path, "new.txt")
        XCTAssertEqual(entry.origPath, "old.txt")
    }

    func testParseStatusConflictEntry() {
        let output = "u UU N... 100644 100644 100644 100644 h h h both.txt\0"
        let result = GitStatusModel.parseStatus(output)

        XCTAssertEqual(result.entries.count, 1)
        let entry = result.entries[0]
        XCTAssertTrue(entry.isConflict)
        XCTAssertEqual(entry.staged, "U")
        XCTAssertEqual(entry.unstaged, "U")
        XCTAssertEqual(entry.path, "both.txt")
    }

    func testParseStatusUntrackedEntry() {
        let output = "? new.txt\0"
        let result = GitStatusModel.parseStatus(output)

        XCTAssertEqual(result.entries.count, 1)
        let entry = result.entries[0]
        XCTAssertEqual(entry.staged, "?")
        XCTAssertEqual(entry.unstaged, "?")
        XCTAssertEqual(entry.path, "new.txt")
    }

    func testParseStatusIgnoredPathIsNotAnEntry() {
        let output = "! build/\0"
        let result = GitStatusModel.parseStatus(output)

        XCTAssertTrue(result.ignoredPaths.contains("build/"))
        XCTAssertTrue(result.entries.isEmpty)
    }

    func testParseStatusEmptyStringYieldsDefaults() {
        XCTAssertEqual(GitStatusModel.parseStatus(""), StatusResult())
    }

    // MARK: - parseNumstat

    func testParseNumstatSumsAdditionsAndDeletionsIgnoringBinaryRows() {
        let output = "3\t1\tfoo\n-\t-\tbin.png\n10\t0\tbar\n"
        let result = GitStatusModel.parseNumstat(output)

        XCTAssertEqual(result.additions, 13)
        XCTAssertEqual(result.deletions, 1)
    }

    // MARK: - parseRecentCommits

    /// Mirrors `git log --pretty=format:%x1e%H%x1f%h%x1f%s%x1f%an%x1f%ct%x1f%P%x1f%D --name-status -z`:
    /// records separated by U+001E, header fields separated by U+001F, a
    /// newline before the first status token, then NUL-separated
    /// status/path tokens (renames carry old-path then new-path).
    func testParseRecentCommitsTwoCommitsWithRename() {
        let header1 = ["aaa111", "aaa", "Initial commit", "Alice", "1700000000", "", ""]
            .joined(separator: "\u{1f}")
        let record1 = header1 + "\n" + "M" + "\u{0}" + "foo.txt" + "\u{0}"

        let header2 = ["bbb222", "bbb", "Rename file", "Bob", "1700003600", "aaa111", "HEAD -> main,origin/main"]
            .joined(separator: "\u{1f}")
        let record2 = header2 + "\n" + "R100" + "\u{0}" + "old.txt" + "\u{0}" + "new.txt" + "\u{0}"

        let output = "\u{1e}" + record1 + "\u{1e}" + record2
        let commits = GitStatusModel.parseRecentCommits(output)

        XCTAssertEqual(commits.count, 2)

        let first = commits[0]
        XCTAssertEqual(first.hash, "aaa111")
        XCTAssertEqual(first.shortHash, "aaa")
        XCTAssertEqual(first.subject, "Initial commit")
        XCTAssertEqual(first.author, "Alice")
        XCTAssertEqual(first.date, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertNil(first.parentHash)
        XCTAssertEqual(first.references, [])
        XCTAssertEqual(first.files.count, 1)
        XCTAssertEqual(first.files[0].status, "M")
        XCTAssertEqual(first.files[0].path, "foo.txt")
        XCTAssertNil(first.files[0].originalPath)

        let second = commits[1]
        XCTAssertEqual(second.hash, "bbb222")
        XCTAssertEqual(second.subject, "Rename file")
        XCTAssertEqual(second.author, "Bob")
        XCTAssertEqual(second.date, Date(timeIntervalSince1970: 1_700_003_600))
        XCTAssertEqual(second.parentHash, "aaa111")
        XCTAssertEqual(second.references, ["HEAD -> main", "origin/main"])
        XCTAssertEqual(second.files.count, 1)
        XCTAssertEqual(second.files[0].status, "R")
        XCTAssertEqual(second.files[0].path, "new.txt")
        XCTAssertEqual(second.files[0].originalPath, "old.txt")
    }
}
