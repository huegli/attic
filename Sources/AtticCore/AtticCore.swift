// =============================================================================
// AtticCore.swift - Public API for the Attic Emulator Core Library
// =============================================================================
//
// This file serves as the main entry point for the AtticCore library.
// It re-exports public types and provides version information.
//
// AtticCore is a shared library used by both the CLI and GUI executables.
// It contains:
// - EmulatorEngine: Thread-safe wrapper around libatari800
// - REPL components: Command parsing and mode management
// - Audio engine: Sound output handling
// - File format handlers: ATR disk images, BASIC tokenizer (future phases)
//
// Usage in other targets:
//
//     import AtticCore
//
//     // Access version information
//     print(AtticCore.version)
//
//     // Create an emulator engine
//     let engine = EmulatorEngine()
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - Public Exports
// =============================================================================
// Re-export types from submodules for convenient access.
// Users can import just AtticCore to get all public types.

// Emulator types
@_exported import struct Foundation.URL

// =============================================================================
// MARK: - Version Information
// =============================================================================

/// AtticCore library namespace containing version information and global utilities.
///
/// This enum serves as a namespace (using a caseless enum pattern common in Swift)
/// to group library-level information that doesn't belong to any specific type.
public enum AtticCore {
    /// The current version of the AtticCore library.
    /// Follows semantic versioning: MAJOR.MINOR.PATCH
    public static let version = "0.1.0"

    /// The name of the application.
    public static let appName = "Attic"

    /// Full application title with version.
    public static var fullTitle: String {
        "\(appName) v\(version)"
    }

    /// Copyright notice.
    public static let copyright = "Copyright (c) 2024"

    /// Build configuration (debug or release).
    public static var buildConfiguration: String {
        #if DEBUG
        return "Debug"
        #else
        return "Release"
        #endif
    }

    /// Welcome banner displayed when the REPL starts.
    ///
    /// This banner is shown to users when they launch the CLI in REPL mode.
    /// It includes version information and basic help hints.
    public static var welcomeBanner: String {
        """
        \(fullTitle) - Atari 800 XL Emulator
        \(copyright)

        Type '.help' for available commands.
        Type '.quit' to exit.

        """
    }
}

// =============================================================================
// MARK: - Error Types
// =============================================================================

/// Errors that can occur during emulator operations.
///
/// This enum consolidates all error types that may be thrown by AtticCore.
/// Each case includes associated values for detailed error information.
///
/// Usage:
///
///     do {
///         try engine.loadROM(at: romPath)
///     } catch AtticError.romNotFound(let path) {
///         print("ROM not found: \(path)")
///     }
///
public enum AtticError: Error, LocalizedError {
    /// The specified ROM file was not found.
    case romNotFound(String)

    /// The ROM file exists but is invalid (wrong size, corrupt, etc.).
    case invalidROM(String)

    /// Failed to load a saved state file.
    case stateLoadFailed(String)

    /// Failed to save state to file.
    case stateSaveFailed(String)

    /// Memory access error (address out of range, etc.).
    case memoryAccessError(String)

    /// The emulator is not initialized.
    case notInitialized

    /// A socket communication error occurred.
    case socketError(String)

    /// Command parsing error with suggestion.
    case invalidCommand(String, suggestion: String?)

    /// File operation error.
    case fileError(String)

    /// Human-readable error description for display.
    public var errorDescription: String? {
        switch self {
        case .romNotFound(let path):
            return "ROM not found: \(path)"
        case .invalidROM(let reason):
            return "Invalid ROM: \(reason)"
        case .stateLoadFailed(let reason):
            return "Failed to load state: \(reason)"
        case .stateSaveFailed(let reason):
            return "Failed to save state: \(reason)"
        case .memoryAccessError(let reason):
            return "Memory access error: \(reason)"
        case .notInitialized:
            return "Emulator not initialized"
        case .socketError(let reason):
            return "Socket error: \(reason)"
        case .invalidCommand(let cmd, let suggestion):
            if let suggestion = suggestion {
                return "Invalid command '\(cmd)'. \(suggestion)"
            }
            return "Invalid command '\(cmd)'"
        case .fileError(let reason):
            return "File error: \(reason)"
        }
    }
}
