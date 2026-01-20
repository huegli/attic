// =============================================================================
// MemoryBus.swift - Memory Access Protocol
// =============================================================================
//
// This file defines the MemoryBus protocol for accessing the Atari 800 XL's
// 64KB address space. The protocol abstracts memory operations so that
// different implementations can be swapped (real emulator vs. mock for testing).
//
// The Atari 800 XL has a complex memory map with ROM, RAM, and hardware
// registers mapped to different address ranges. See ARCHITECTURE.md for the
// complete memory map.
//
// Key address ranges:
// - $0000-$00FF: Zero Page (fast access)
// - $0100-$01FF: Hardware Stack
// - $0200-$05FF: OS variables and device handlers
// - $0600-$9FFF: User RAM (can be under ROM in some areas)
// - $D000-$D4FF: Hardware registers (GTIA, POKEY, PIA, ANTIC)
// - $E000-$FFFF: OS ROM
//
// Usage:
//
//     // Read a byte
//     let value = memoryBus.read(0x0600)
//
//     // Write a byte
//     memoryBus.write(0x0600, value: 0xA9)
//
//     // Read a block of memory
//     let bytes = memoryBus.readBlock(from: 0x0600, count: 256)
//
// =============================================================================

import Foundation

/// Protocol defining memory access operations for the emulator.
///
/// Implementations must handle the full 64KB address space of the 6502,
/// including ROM/RAM banking and hardware register access.
///
/// All operations are synchronous. For thread-safe access, use the
/// EmulatorEngine actor which serializes memory operations.
public protocol MemoryBus: Sendable {
    /// Reads a single byte from the specified address.
    ///
    /// - Parameter address: The 16-bit address to read from (0x0000-0xFFFF).
    /// - Returns: The byte value at that address.
    func read(_ address: UInt16) -> UInt8

    /// Writes a single byte to the specified address.
    ///
    /// Note: Writes to ROM addresses are typically ignored unless RAM is
    /// banked in at that location.
    ///
    /// - Parameters:
    ///   - address: The 16-bit address to write to (0x0000-0xFFFF).
    ///   - value: The byte value to write.
    func write(_ address: UInt16, value: UInt8)

    /// Reads a block of bytes starting at the specified address.
    ///
    /// This is more efficient than calling read() repeatedly for large reads.
    ///
    /// - Parameters:
    ///   - from: The starting address.
    ///   - count: Number of bytes to read.
    /// - Returns: Array of bytes read from memory.
    func readBlock(from address: UInt16, count: Int) -> [UInt8]

    /// Writes a block of bytes starting at the specified address.
    ///
    /// This is more efficient than calling write() repeatedly for large writes.
    ///
    /// - Parameters:
    ///   - at: The starting address.
    ///   - bytes: Array of bytes to write.
    func writeBlock(at address: UInt16, bytes: [UInt8])
}

// =============================================================================
// MARK: - Default Implementations
// =============================================================================

extension MemoryBus {
    /// Default implementation of readBlock using repeated single reads.
    ///
    /// Concrete implementations should override this for better performance.
    public func readBlock(from address: UInt16, count: Int) -> [UInt8] {
        var result = [UInt8]()
        result.reserveCapacity(count)

        for offset in 0..<count {
            // Handle address wrapping at 64KB boundary
            let addr = address &+ UInt16(offset)
            result.append(read(addr))
        }

        return result
    }

    /// Default implementation of writeBlock using repeated single writes.
    ///
    /// Concrete implementations should override this for better performance.
    public func writeBlock(at address: UInt16, bytes: [UInt8]) {
        for (offset, byte) in bytes.enumerated() {
            // Handle address wrapping at 64KB boundary
            let addr = address &+ UInt16(offset)
            write(addr, value: byte)
        }
    }

    /// Reads a 16-bit word (little-endian) from the specified address.
    ///
    /// The 6502 uses little-endian byte order, so the low byte comes first.
    ///
    /// - Parameter address: The starting address.
    /// - Returns: The 16-bit value (low byte at address, high byte at address+1).
    public func readWord(_ address: UInt16) -> UInt16 {
        let low = UInt16(read(address))
        let high = UInt16(read(address &+ 1))
        return (high << 8) | low
    }

    /// Writes a 16-bit word (little-endian) to the specified address.
    ///
    /// - Parameters:
    ///   - address: The starting address.
    ///   - value: The 16-bit value to write.
    public func writeWord(_ address: UInt16, value: UInt16) {
        write(address, value: UInt8(value & 0xFF))
        write(address &+ 1, value: UInt8(value >> 8))
    }
}

// =============================================================================
// MARK: - Memory Regions
// =============================================================================

/// Constants for important memory regions in the Atari 800 XL.
///
/// These addresses are used throughout the emulator for accessing
/// specific hardware features and system data.
public enum MemoryRegion {
    // Zero Page locations
    public static let zeroPageStart: UInt16 = 0x0000
    public static let zeroPageEnd: UInt16 = 0x00FF

    // Hardware stack
    public static let stackStart: UInt16 = 0x0100
    public static let stackEnd: UInt16 = 0x01FF

    // OS and device handler areas
    public static let osVariablesStart: UInt16 = 0x0200
    public static let deviceHandlersEnd: UInt16 = 0x05FF

    // User RAM (typical BASIC program area)
    public static let userRAMStart: UInt16 = 0x0600

    // BASIC program area (when BASIC is enabled)
    public static let basicLOMEM: UInt16 = 0x0700

    // Hardware registers
    public static let gtiaStart: UInt16 = 0xD000
    public static let pokeyStart: UInt16 = 0xD200
    public static let piaStart: UInt16 = 0xD300
    public static let anticStart: UInt16 = 0xD400

    // ROM areas
    public static let basicROMStart: UInt16 = 0xA000
    public static let basicROMEnd: UInt16 = 0xBFFF
    public static let osROMStart: UInt16 = 0xE000
    public static let resetVector: UInt16 = 0xFFFC
    public static let irqVector: UInt16 = 0xFFFE
}
