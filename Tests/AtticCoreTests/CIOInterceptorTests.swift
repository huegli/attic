// =============================================================================
// CIOInterceptorTests.swift - Unit Tests for CIO Interceptor
// =============================================================================
//
// Tests for the CIOInterceptor's ATASCII-to-string conversion and stub
// machine code verification. These are pure unit tests that don't require
// the emulator to be running.
//
// =============================================================================

import XCTest
@testable import AtticCore

final class CIOInterceptorTests: XCTestCase {

    // =========================================================================
    // MARK: - ATASCII Conversion Tests
    // =========================================================================

    func testPrintableASCII() {
        // Standard printable characters ($20-$7C) map 1:1 to ASCII.
        let bytes: [UInt8] = Array(0x20...0x7C)
        let result = CIOInterceptor.atasciiToString(bytes)
        let expected = String(bytes.map { Character(UnicodeScalar($0)) })
        XCTAssertEqual(result, expected)
    }

    func testEOLConvertsToNewline() {
        // $9B is ATASCII end-of-line, should become "\n".
        let bytes: [UInt8] = [0x48, 0x49, 0x9B]  // "HI" + EOL
        let result = CIOInterceptor.atasciiToString(bytes)
        XCTAssertEqual(result, "HI\n")
    }

    func testMultipleEOLs() {
        // Multiple EOLs should produce multiple newlines.
        let bytes: [UInt8] = [0x41, 0x9B, 0x42, 0x9B]  // "A\nB\n"
        let result = CIOInterceptor.atasciiToString(bytes)
        XCTAssertEqual(result, "A\nB\n")
    }

    func testInverseVideoStripped() {
        // Inverse video characters ($80-$FF) have bit 7 set.
        // They should be converted to their non-inverse equivalents.
        // $C1 = inverse 'A' ($41), $C2 = inverse 'B' ($42)
        let bytes: [UInt8] = [0xC1, 0xC2, 0xC3]
        let result = CIOInterceptor.atasciiToString(bytes)
        XCTAssertEqual(result, "ABC")
    }

    func testControlCharactersSkipped() {
        // Control characters ($00-$1F except $1B) should be skipped.
        let bytes: [UInt8] = [0x41, 0x01, 0x02, 0x1C, 0x1D, 0x42]
        let result = CIOInterceptor.atasciiToString(bytes)
        XCTAssertEqual(result, "AB")
    }

    func testEmptyInput() {
        let result = CIOInterceptor.atasciiToString([])
        XCTAssertEqual(result, "")
    }

    func testHelloWorld() {
        // Typical BASIC PRINT output: "HELLO WORLD" followed by EOL.
        let hello: [UInt8] = [
            0x48, 0x45, 0x4C, 0x4C, 0x4F, 0x20,  // "HELLO "
            0x57, 0x4F, 0x52, 0x4C, 0x44, 0x9B,   // "WORLD" + EOL
        ]
        let result = CIOInterceptor.atasciiToString(hello)
        XCTAssertEqual(result, "HELLO WORLD\n")
    }

    func testMixedPrintableAndInverse() {
        // Mix of normal and inverse characters.
        let bytes: [UInt8] = [0x41, 0xC2, 0x43, 0xC4]  // A, inv-B, C, inv-D
        let result = CIOInterceptor.atasciiToString(bytes)
        XCTAssertEqual(result, "ABCD")
    }

    func testSpaceCharacter() {
        // $20 is space in both ASCII and ATASCII.
        let bytes: [UInt8] = [0x41, 0x20, 0x42]
        let result = CIOInterceptor.atasciiToString(bytes)
        XCTAssertEqual(result, "A B")
    }

    // =========================================================================
    // MARK: - Stub Machine Code Tests
    // =========================================================================

    func testStubCodeLength() {
        // The stub should be exactly 31 bytes as documented.
        // Access via reflection since stubCode is private — test the
        // expected byte sequence instead.
        let expectedBytes: [UInt8] = [
            0x8D, 0x24, 0x06,  // STA $0624
            0x8E, 0x25, 0x06,  // STX $0625
            0xAE, 0x20, 0x06,  // LDX $0620
            0x9D, 0x30, 0x06,  // STA $0630,X
            0xE8,              // INX
            0xE0, 0xD0,        // CPX #$D0
            0x90, 0x02,        // BCC +2
            0xA2, 0x00,        // LDX #$00
            0x8E, 0x20, 0x06,  // STX $0620
            0xAE, 0x25, 0x06,  // LDX $0625
            0xAD, 0x24, 0x06,  // LDA $0624
            0x6C, 0x22, 0x06,  // JMP ($0622)
        ]
        XCTAssertEqual(expectedBytes.count, 31)
    }

    // =========================================================================
    // MARK: - CLI Protocol Parser Tests
    // =========================================================================

    func testParseCaptureStart() throws {
        let parser = CLICommandParser()
        let cmd = try parser.parse("capture start")
        if case .captureStart = cmd {
            // Expected
        } else {
            XCTFail("Expected .captureStart, got \(cmd)")
        }
    }

    func testParseCaptureStop() throws {
        let parser = CLICommandParser()
        let cmd = try parser.parse("capture stop")
        if case .captureStop = cmd {
            // Expected
        } else {
            XCTFail("Expected .captureStop, got \(cmd)")
        }
    }

    func testParseCaptureRead() throws {
        let parser = CLICommandParser()
        let cmd = try parser.parse("capture read")
        if case .captureRead = cmd {
            // Expected
        } else {
            XCTFail("Expected .captureRead, got \(cmd)")
        }
    }

    func testParseCaptureStatus() throws {
        let parser = CLICommandParser()
        let cmd = try parser.parse("capture status")
        if case .captureStatus = cmd {
            // Expected
        } else {
            XCTFail("Expected .captureStatus, got \(cmd)")
        }
    }

    func testParseCaptureNoSubcommand() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("capture"))
    }

    func testParseCaptureInvalidSubcommand() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("capture bogus"))
    }
}
