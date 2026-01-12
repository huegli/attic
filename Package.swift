// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

// =============================================================================
// Package.swift - Swift Package Manager Configuration for Attic
// =============================================================================
//
// This file defines the Attic project structure for the Swift Package Manager.
// It configures three main targets:
//
// 1. AtticCore - A shared library containing the emulator engine, REPL logic,
//    BASIC tokenizer, and file format handlers. Both CLI and GUI depend on this.
//
// 2. AtticCLI (attic) - The command-line executable that provides a REPL
//    interface for interacting with the emulator. Designed for Emacs comint mode.
//
// 3. AtticGUI - The SwiftUI application with Metal rendering for display output.
//
// The package also integrates with libatari800, a pre-compiled C library that
// provides the actual Atari 800 XL emulation. This is linked via a system library
// target with a custom module map.
//
// IMPORTANT: Before building, you must place the libatari800 files:
//   - Libraries/libatari800/lib/libatari800.a (static library)
//   - Libraries/libatari800/include/libatari800.h (header file)
//
// =============================================================================

import PackageDescription

let package = Package(
    // Package name - appears in build output and error messages
    name: "Attic",

    // Minimum platform requirements
    // macOS 15 (Sequoia) is required for the latest SwiftUI and Metal features
    platforms: [
        .macOS(.v15)
    ],

    // Products are the artifacts that can be used by other packages or run directly
    products: [
        // AtticCore library - can be imported by other Swift packages if needed
        .library(
            name: "AtticCore",
            targets: ["AtticCore"]
        ),
        // AtticProtocol library - AESP protocol for emulator/client communication
        .library(
            name: "AtticProtocol",
            targets: ["AtticProtocol"]
        ),
        // CLI executable - named "attic" for command-line use
        .executable(
            name: "attic",
            targets: ["AtticCLI"]
        ),
        // GUI executable - named "AtticGUI" for the SwiftUI application
        .executable(
            name: "AtticGUI",
            targets: ["AtticGUI"]
        ),
        // Server executable - standalone emulator server using AESP protocol
        .executable(
            name: "AtticServer",
            targets: ["AtticServer"]
        )
    ],

    // Target definitions
    targets: [
        // =================================================================
        // CAtari800 - System Library for libatari800 C interop
        // =================================================================
        // This target doesn't contain Swift code. Instead, it provides a
        // module map that allows Swift to import the C library functions.
        // The module map is located at Libraries/libatari800/module.modulemap
        .systemLibrary(
            name: "CAtari800",
            path: "Libraries/libatari800"
        ),

        // =================================================================
        // AtticProtocol - AESP Protocol Library
        // =================================================================
        // Implements the Attic Emulator Server Protocol (AESP) for
        // communication between the emulator server and GUI/web clients.
        // This enables separating the emulator into a standalone process.
        // - AESPMessage: Binary message encoding/decoding
        // - AESPMessageType: Protocol message types
        // - AESPServer: Server actor for broadcasting frames/audio
        // - AESPClient: Client actor for connecting to servers
        .target(
            name: "AtticProtocol",
            dependencies: [],
            path: "Sources/AtticProtocol"
        ),

        // =================================================================
        // AtticCore - Shared Library
        // =================================================================
        // Contains all the core functionality shared between CLI and GUI:
        // - EmulatorEngine: Actor that wraps libatari800 for thread-safe access
        // - REPL components: Command parsing, mode management
        // - Audio engine: Sound output handling
        // - File format handlers: ATR disk images, BASIC tokenizer (future)
        .target(
            name: "AtticCore",
            dependencies: ["CAtari800"],
            path: "Sources/AtticCore",
            linkerSettings: [
                // Link against the local libatari800.a static library
                .unsafeFlags(["-L", "Libraries/libatari800/lib"]),
                // Also need to link zlib which libatari800 depends on
                .linkedLibrary("z")
            ]
        ),

        // =================================================================
        // AtticCLI - Command-Line Executable
        // =================================================================
        // The REPL interface for the emulator. Features:
        // - Argument parsing (--repl, --headless, --silent, --socket)
        // - Three modes: Monitor (debugging), BASIC, DOS (disk management)
        // - Unix socket communication with GUI when not in headless mode
        // - Designed for Emacs comint-mode compatibility
        .executableTarget(
            name: "AtticCLI",
            dependencies: ["AtticCore"],
            path: "Sources/AtticCLI"
        ),

        // =================================================================
        // AtticGUI - SwiftUI Application
        // =================================================================
        // The graphical interface with:
        // - Metal-based rendering at 60fps
        // - Core Audio output
        // - Keyboard and game controller input
        // - Unix socket server for CLI communication
        .executableTarget(
            name: "AtticGUI",
            dependencies: ["AtticCore"],
            path: "Sources/AtticGUI"
        ),

        // =================================================================
        // AtticServer - Standalone Emulator Server
        // =================================================================
        // A headless emulator server that broadcasts video frames and audio
        // samples via the Attic Emulator Server Protocol (AESP).
        // Clients (GUI, web browser) connect to receive streams.
        // - Runs EmulatorEngine in server mode
        // - Broadcasts frames at 60fps to video subscribers
        // - Broadcasts audio samples to audio subscribers
        // - Handles control commands from connected clients
        .executableTarget(
            name: "AtticServer",
            dependencies: ["AtticCore", "AtticProtocol"],
            path: "Sources/AtticServer"
        ),

        // =================================================================
        // AtticCoreTests - Unit Tests
        // =================================================================
        // Test suite for the core library components
        .testTarget(
            name: "AtticCoreTests",
            dependencies: ["AtticCore"],
            path: "Tests/AtticCoreTests"
        ),

        // =================================================================
        // AtticProtocolTests - AESP Protocol Tests
        // =================================================================
        // Test suite for the AESP protocol library including:
        // - Message encoding/decoding unit tests
        // - Server integration tests
        // - Client-server communication tests
        .testTarget(
            name: "AtticProtocolTests",
            dependencies: ["AtticProtocol", "AtticCore"],
            path: "Tests/AtticProtocolTests"
        )
    ]
)
