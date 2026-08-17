//
//  GitProcess.swift
//  kero
//

import Darwin
import Dispatch
import Foundation

/// Shared runner behind every direct `/usr/bin/git` invocation. Returns raw
/// bytes and leaves decoding to the caller: `GitStatusModel.runGit` decodes
/// to `String`, while diff blob reads need the original bytes so invalid
/// UTF-8 and embedded NULs cannot be mistaken for an empty text file.
///
/// Dedicated reader threads are intentional: several restored diff tabs can
/// call this from Swift's cooperative executor at once, and dispatching the
/// readers back onto the shared pool can starve every pipe drain.
nonisolated enum GitProcess {
    struct Result: Sendable {
        let status: Int32
        let stdout: Data
        let stderr: Data
        let timedOut: Bool
    }

    private final class PipeData: @unchecked Sendable {
        var value = Data()
    }

    static func run(
        _ args: [String], in directory: String, timeout: TimeInterval?, stdoutLimit: Int? = nil
    ) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        var env = ProcessInfo.processInfo.environment
        env["GIT_OPTIONAL_LOCKS"] = "0"
        // Fail rather than hanging on a credential prompt behind the app.
        env["GIT_TERMINAL_PROMPT"] = "0"
        // Git diagnostics are parsed only to distinguish an ordinary folder
        // from a broken repository. Pinning the locale makes that safe and
        // also keeps relative dates stable in the compact history list.
        env["LC_ALL"] = "C"
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice
        let processExited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in processExited.signal() }

        do {
            try process.run()
        } catch {
            return Result(
                status: -1,
                stdout: Data(),
                stderr: Data(error.localizedDescription.utf8),
                timedOut: false
            )
        }
        let outData = PipeData()
        let errData = PipeData()
        let readers = DispatchGroup()
        // These readers are on the synchronous completion path below. Match
        // the caller so a user-initiated Git request never waits on utility
        // threads, while background refreshes keep their lower priority.
        let readerQualityOfService = Thread.current.qualityOfService
        readers.enter()
        let stdoutReader = Thread {
            if let stdoutLimit {
                // Drain the pipe so Git cannot deadlock, but retain at most
                // one byte beyond the limit. The index may change between
                // cat-file's size check and this read while an agent is
                // working.
                while true {
                    let chunk: Data
                    do {
                        guard let next = try stdout.fileHandleForReading.read(upToCount: 64 * 1024),
                              !next.isEmpty else { break }
                        chunk = next
                    } catch {
                        break
                    }
                    let remaining = stdoutLimit - outData.value.count
                    if remaining > 0 {
                        outData.value.append(chunk.prefix(remaining))
                    }
                }
            } else {
                outData.value = stdout.fileHandleForReading.readDataToEndOfFile()
            }
            readers.leave()
        }
        stdoutReader.qualityOfService = readerQualityOfService
        stdoutReader.start()
        readers.enter()
        let stderrReader = Thread {
            errData.value = stderr.fileHandleForReading.readDataToEndOfFile()
            readers.leave()
        }
        stderrReader.qualityOfService = readerQualityOfService
        stderrReader.start()
        var timedOut = false
        if let timeout {
            timedOut = processExited.wait(timeout: .now() + timeout) == .timedOut
            if timedOut {
                process.terminate()
                if processExited.wait(timeout: .now() + 1) == .timedOut {
                    // Git can launch a helper that ignores SIGTERM. It is our
                    // child, so force it down before waiting for pipe EOF.
                    Darwin.kill(process.processIdentifier, SIGKILL)
                    process.waitUntilExit()
                }
            }
        } else {
            process.waitUntilExit()
        }
        readers.wait()
        return Result(
            status: process.terminationStatus,
            stdout: outData.value,
            stderr: errData.value,
            timedOut: timedOut
        )
    }
}
