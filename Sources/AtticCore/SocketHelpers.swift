// =============================================================================
// SocketHelpers.swift - Shared Socket Utilities
// =============================================================================
//
// This file provides Swift-friendly wrappers for low-level socket operations,
// particularly the C fd_set macros used with select() for I/O multiplexing.
//
// These helpers are used by both CLISocketClient and CLISocketServer to monitor
// file descriptors for readiness without blocking other async tasks.
//
// =============================================================================

import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// =============================================================================
// MARK: - fd_set Helpers
// =============================================================================

/// Clears an fd_set, removing all file descriptors from the set.
///
/// fd_set is a data structure used with select() to specify which file
/// descriptors to monitor for I/O readiness. This function initializes
/// the set to empty.
///
/// - Parameter set: The fd_set to clear.
func fdZero(_ set: inout fd_set) {
    #if canImport(Darwin)
    // macOS: __darwin_fd_set is an array of Int32
    _ = withUnsafeMutablePointer(to: &set) { ptr in
        memset(ptr, 0, MemoryLayout<fd_set>.size)
    }
    #else
    // Linux: Use the provided macro
    __FD_ZERO(&set)
    #endif
}

/// Adds a file descriptor to an fd_set.
///
/// After calling this function, select() will monitor the specified
/// file descriptor when the fd_set is passed as a read, write, or
/// exception set.
///
/// - Parameters:
///   - fd: The file descriptor to add (e.g., a socket).
///   - set: The fd_set to modify.
func fdSet(_ fd: Int32, _ set: inout fd_set) {
    #if canImport(Darwin)
    let intOffset = Int(fd) / 32
    let bitOffset = Int(fd) % 32
    withUnsafeMutablePointer(to: &set) { ptr in
        let rawPtr = UnsafeMutableRawPointer(ptr)
        let arrayPtr = rawPtr.assumingMemoryBound(to: Int32.self)
        arrayPtr[intOffset] |= Int32(1 << bitOffset)
    }
    #else
    __FD_SET(fd, &set)
    #endif
}

/// Checks if a file descriptor is set in an fd_set.
///
/// After select() returns, use this function to check whether a
/// specific file descriptor is ready for the operation (read/write/exception).
///
/// - Parameters:
///   - fd: The file descriptor to check.
///   - set: The fd_set to query.
/// - Returns: True if the file descriptor is set, false otherwise.
func fdIsSet(_ fd: Int32, _ set: inout fd_set) -> Bool {
    #if canImport(Darwin)
    let intOffset = Int(fd) / 32
    let bitOffset = Int(fd) % 32
    return withUnsafeMutablePointer(to: &set) { ptr -> Bool in
        let rawPtr = UnsafeMutableRawPointer(ptr)
        let arrayPtr = rawPtr.assumingMemoryBound(to: Int32.self)
        return (arrayPtr[intOffset] & Int32(1 << bitOffset)) != 0
    }
    #else
    return __FD_ISSET(fd, &set) != 0
    #endif
}
