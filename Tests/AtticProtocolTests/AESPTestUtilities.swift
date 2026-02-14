// =============================================================================
// AESPTestUtilities.swift - Shared Test Utilities for AESP Protocol Tests
// =============================================================================
//
// This file provides shared utilities used across AESP protocol test files.
// Currently includes a process guard that ensures no Attic processes
// (AtticServer, AtticMCP, AtticGUI, attic CLI) are running before tests
// that open network ports.
//
// =============================================================================

import Foundation
import XCTest

// =============================================================================
// MARK: - Process Guard
// =============================================================================

/// Ensures no Attic processes are running before tests.
///
/// Networking tests open TCP ports (48xxx, 49xxx). While these don't overlap
/// with the default AESP ports (47800-47802), a running server or client could
/// cause unexpected interference (e.g. AtticGUI auto-launches AtticServer).
/// This guard checks once per test run and kills any stale Attic processes.
///
/// Usage: Call `AESPTestProcessGuard.ensureClean()` from `setUp()` of
/// any test class that opens network ports.
enum AESPTestProcessGuard {

    /// Whether the guard has already run this test session.
    /// Uses nonisolated(unsafe) because tests run serially in XCTest and
    /// the flag is only ever written once (on first call).
    nonisolated(unsafe) private static var hasChecked = false

    /// Process names to check for and kill.
    /// Includes servers (AtticServer, AtticMCP) and clients (AtticGUI, attic CLI)
    /// because clients may auto-launch servers or hold open AESP connections.
    private static let serverProcessNames = ["AtticServer", "AtticMCP", "AtticGUI", "attic"]

    /// Checks for running server processes and kills them if found.
    ///
    /// On first call: runs `pgrep` for each process name. If any are found,
    /// sends SIGTERM, waits 1 second, then verifies they exited.
    /// On subsequent calls: returns immediately (no-op).
    ///
    /// - Parameters:
    ///   - file: Source file for XCTFail (auto-filled by caller).
    ///   - line: Source line for XCTFail (auto-filled by caller).
    static func ensureClean(file: StaticString = #filePath, line: UInt = #line) {
        guard !hasChecked else { return }
        hasChecked = true

        for name in serverProcessNames {
            // Check if the process is running using pgrep -x (exact name match)
            let pids = findProcesses(named: name)
            guard !pids.isEmpty else { continue }

            print("[AESPTestProcessGuard] Found running \(name) (PIDs: \(pids)). Terminating...")

            // Send SIGTERM to each PID
            for pid in pids {
                let kill = Process()
                kill.executableURL = URL(fileURLWithPath: "/bin/kill")
                kill.arguments = ["-TERM", String(pid)]
                try? kill.run()
                kill.waitUntilExit()
            }

            // Wait for processes to exit gracefully
            Thread.sleep(forTimeInterval: 1.0)

            // Verify they're gone
            let remaining = findProcesses(named: name)
            if !remaining.isEmpty {
                // Force kill as last resort
                print("[AESPTestProcessGuard] \(name) still running after SIGTERM. Sending SIGKILL...")
                for pid in remaining {
                    let kill = Process()
                    kill.executableURL = URL(fileURLWithPath: "/bin/kill")
                    kill.arguments = ["-KILL", String(pid)]
                    try? kill.run()
                    kill.waitUntilExit()
                }
                Thread.sleep(forTimeInterval: 0.5)

                let stillRunning = findProcesses(named: name)
                if !stillRunning.isEmpty {
                    XCTFail(
                        "\(name) is still running (PIDs: \(stillRunning)) after kill attempts. "
                        + "Please stop it manually before running protocol tests.",
                        file: file, line: line
                    )
                }
            }

            print("[AESPTestProcessGuard] \(name) terminated successfully.")
        }
    }

    /// Finds PIDs of processes with the given exact name.
    ///
    /// Uses `pgrep -x` for exact name matching (won't match substrings
    /// like "swift test --filter AtticServer").
    ///
    /// - Parameter name: The exact process name to search for.
    /// - Returns: Array of PIDs, empty if no matching processes found.
    private static func findProcesses(named name: String) -> [Int32] {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-x", name]

        let pipe = Pipe()
        pgrep.standardOutput = pipe
        pgrep.standardError = FileHandle.nullDevice

        do {
            try pgrep.run()
            pgrep.waitUntilExit()
        } catch {
            return []
        }

        // pgrep exit code 0 = found, 1 = not found
        guard pgrep.terminationStatus == 0 else { return [] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        return output
            .split(separator: "\n")
            .compactMap { Int32(String($0).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)) }
    }
}
