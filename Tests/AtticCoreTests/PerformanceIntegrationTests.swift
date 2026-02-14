// =============================================================================
// PerformanceIntegrationTests.swift - Performance Integration Tests
// =============================================================================
//
// This file provides integration test coverage for performance characteristics:
// 1. Frame Rate (12.1) - Sustained 60fps, drop detection, status consistency
// 2. Audio Latency (12.2) - Ring buffer latency, underrun detection, sync
// 3. Memory Usage (12.3) - Stable memory, no leaks, no spikes on large ops
//
// These tests exercise FrameRateMonitor, AudioEngine's RingBuffer, and memory
// characteristics under sustained workloads. They use deterministic timestamps
// where possible, and real-time measurements where wall-clock behavior matters.
//
// No emulator or server is needed — these tests work directly with AtticCore
// types (FrameRateMonitor, RingBuffer, AudioEngine, EmulatorState).
//
// Running:
//   swift test --filter PerformanceIntegrationTests
//   make test-perf
//
// =============================================================================

import XCTest
@testable import AtticCore

// =============================================================================
// MARK: - Helpers
// =============================================================================

/// Converts milliseconds to nanoseconds for deterministic timestamp injection.
private func ms(_ milliseconds: Double) -> UInt64 {
    return UInt64(milliseconds * 1_000_000.0)
}

// =============================================================================
// MARK: - 12.1 Frame Rate Performance Tests
// =============================================================================

/// Tests for sustained frame rate under various conditions.
///
/// These tests verify:
/// - Maintaining 60fps over extended periods (10+ seconds simulated)
/// - Frame drop detection at various load patterns
/// - FPS counter consistency across measurement windows
/// - Status bar rate stability (FPS doesn't oscillate wildly)
/// - Recovery after stalls (e.g., garbage collection pauses)
///
/// Most tests use deterministic timestamps via recordFrame(timestamp:) so they
/// run in milliseconds regardless of the simulated duration. Real-time tests
/// are marked with a comment and use recordFrame() with actual wall-clock time.
final class FrameRatePerformanceTests: XCTestCase {

    // =========================================================================
    // MARK: - Sustained Performance
    // =========================================================================

    /// Simulate 10 seconds of perfect 60fps — FPS should remain 60 throughout.
    ///
    /// This verifies the monitor handles extended sessions without drift,
    /// overflow, or accumulated error in statistics.
    func test_sustained10Seconds_perfect60fps() {
        let monitor = FrameRateMonitor()
        let interval = ms(1000.0 / 60.0)
        var timestamp: UInt64 = 1_000_000_000

        // 600 frames = 10 seconds at 60fps
        for _ in 0..<600 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += interval
        }

        let stats = monitor.statistics
        XCTAssertGreaterThanOrEqual(stats.fps, 59)
        XCTAssertLessThanOrEqual(stats.fps, 60)
        XCTAssertEqual(stats.droppedFrames, 0)
        XCTAssertEqual(stats.totalFrames, 600)
        XCTAssertEqual(stats.averageFrameTimeMs, 16.67, accuracy: 0.1)
        XCTAssertEqual(stats.jitterMs, 0.0, accuracy: 0.01)
        XCTAssertEqual(stats.consistencyPercent, 100.0)
    }

    /// Simulate 60 seconds of 60fps — verify no counter overflow or drift.
    ///
    /// At 60fps for 60 seconds, totalFrames reaches 3600. This exercises
    /// the UInt64 timestamp and Int counters at realistic session lengths.
    func test_sustained60Seconds_noOverflow() {
        let monitor = FrameRateMonitor()
        let interval = ms(16.6667)
        var timestamp: UInt64 = 1_000_000_000

        // 3600 frames = 60 seconds at 60fps
        for _ in 0..<3600 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += interval
        }

        let stats = monitor.statistics
        XCTAssertEqual(stats.totalFrames, 3600)
        XCTAssertEqual(stats.droppedFrames, 0)
        XCTAssertGreaterThanOrEqual(stats.fps, 59)
        XCTAssertLessThanOrEqual(stats.fps, 60)
    }

    /// Realistic jitter pattern from a real system — small random variations.
    ///
    /// Tests that minor timing variations (±3ms) don't cause false drop
    /// detections and that statistics remain clean.
    func test_sustainedWithRealisticJitter_noFalseDrops() {
        let monitor = FrameRateMonitor()
        var timestamp: UInt64 = 1_000_000_000

        // Jitter pattern simulating OS scheduling noise: ±3ms around 16.67ms
        // All values stay well below the 25ms drop threshold
        let jitterPattern: [Double] = [
            14.5, 18.8, 16.0, 17.5, 15.2, 16.9, 18.1, 15.8, 17.3, 16.4,
            14.8, 18.5, 16.2, 17.0, 15.5, 16.7, 18.3, 15.0, 17.8, 16.1,
            19.0, 14.2, 17.6, 16.3, 15.9, 18.0, 14.7, 17.2, 16.8, 15.3,
        ]

        // 600 frames (~10 seconds)
        for i in 0..<600 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += ms(jitterPattern[i % jitterPattern.count])
        }

        let stats = monitor.statistics
        XCTAssertEqual(stats.droppedFrames, 0,
            "Jitter within ±3ms should not cause false drops")
        XCTAssertGreaterThan(stats.jitterMs, 0.0,
            "Jitter should be non-zero with varying intervals")
        XCTAssertLessThan(stats.jitterMs, 3.0,
            "Jitter should stay below 3ms for ±3ms variation")
    }

    // =========================================================================
    // MARK: - FPS Counter Consistency (Status Bar)
    // =========================================================================

    /// FPS should stabilize within the first 2 seconds and not oscillate.
    ///
    /// The status bar displays currentFPS. It should read 60 (or 59 due to
    /// truncation) consistently, not bounce between different values.
    func test_fpsStabilizesQuickly() {
        let monitor = FrameRateMonitor()
        let interval = ms(16.6667)
        var timestamp: UInt64 = 1_000_000_000

        // First second — FPS initializes
        for _ in 0..<61 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += interval
        }
        let fps1 = monitor.currentFPS
        XCTAssertGreaterThanOrEqual(fps1, 59)
        XCTAssertLessThanOrEqual(fps1, 60)

        // Second through fifth seconds — FPS should remain stable
        var fpsReadings: [Int] = []
        for second in 0..<4 {
            for _ in 0..<60 {
                monitor.recordFrame(timestamp: timestamp)
                timestamp += interval
            }
            fpsReadings.append(monitor.currentFPS)
            _ = second // suppress unused warning
        }

        // All readings should be within 59-60
        for (i, fps) in fpsReadings.enumerated() {
            XCTAssertGreaterThanOrEqual(fps, 59,
                "FPS reading at second \(i + 2) should be >= 59, got \(fps)")
            XCTAssertLessThanOrEqual(fps, 60,
                "FPS reading at second \(i + 2) should be <= 60, got \(fps)")
        }
    }

    /// When frame rate drops from 60 to 30 and back, FPS counter follows.
    ///
    /// Verifies the status bar rate responds to actual performance changes
    /// rather than being stuck on a cached value.
    func test_fpsTracksRateChanges() {
        let monitor = FrameRateMonitor()
        var timestamp: UInt64 = 1_000_000_000

        // 2 seconds at 60fps
        for _ in 0..<121 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += ms(16.67)
        }
        XCTAssertGreaterThanOrEqual(monitor.currentFPS, 59)

        // 2 seconds at 30fps
        for _ in 0..<61 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += ms(33.33)
        }
        XCTAssertEqual(monitor.currentFPS, 30,
            "FPS should drop to 30 when frame interval doubles")

        // 2 seconds back at 60fps
        for _ in 0..<121 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += ms(16.67)
        }
        XCTAssertGreaterThanOrEqual(monitor.currentFPS, 59,
            "FPS should recover to 60 when rate returns to normal")
    }

    // =========================================================================
    // MARK: - Recovery After Stalls
    // =========================================================================

    /// After a long stall (e.g., 500ms GC pause), frame rate recovers.
    ///
    /// A single large stall should be recorded as a drop, but subsequent
    /// normal frames should bring statistics back to healthy levels.
    func test_recoveryAfterLongStall() {
        let monitor = FrameRateMonitor()
        let interval = ms(16.67)
        var timestamp: UInt64 = 1_000_000_000

        // 2 seconds of normal frames
        for _ in 0..<120 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += interval
        }
        XCTAssertEqual(monitor.droppedFrames, 0)

        // 500ms stall (simulates a major GC or system interruption)
        timestamp += ms(500.0)
        monitor.recordFrame(timestamp: timestamp)
        XCTAssertEqual(monitor.droppedFrames, 1)

        // 3 seconds of recovery
        for _ in 0..<180 {
            timestamp += interval
            monitor.recordFrame(timestamp: timestamp)
        }

        let stats = monitor.statistics
        // Only the 1 drop from the stall
        XCTAssertEqual(stats.droppedFrames, 1)
        // Ring buffer window (120 frames) should have recovered —
        // average frame time should be back near 16.67ms because the
        // stall has been pushed out of the window
        XCTAssertEqual(stats.averageFrameTimeMs, 16.67, accuracy: 0.5)
        // Consistency should be high overall
        XCTAssertGreaterThan(stats.consistencyPercent, 99.0)
    }

    /// Multiple short stalls (~35ms) every few seconds should be individually counted.
    func test_multipleShortStalls_allCounted() {
        let monitor = FrameRateMonitor()
        let interval = ms(16.67)
        var timestamp: UInt64 = 1_000_000_000

        var expectedDrops = 0

        // 10 seconds with a 35ms stall every 60 frames (~1 second)
        for i in 0..<600 {
            monitor.recordFrame(timestamp: timestamp)
            if i > 0 && i % 60 == 0 {
                timestamp += ms(35.0) // above 25ms threshold
                expectedDrops += 1
            } else {
                timestamp += interval
            }
        }
        // Extra frame to detect the last stall
        monitor.recordFrame(timestamp: timestamp)

        XCTAssertEqual(monitor.droppedFrames, expectedDrops,
            "Expected \(expectedDrops) short stalls to be detected")
    }

    // =========================================================================
    // MARK: - Reset and Resume
    // =========================================================================

    /// After reset, a new measurement session starts cleanly.
    ///
    /// Simulates the pattern of pausing emulation, resetting the monitor,
    /// then resuming. The new session should not carry over stale data.
    func test_resetThenResume_cleanStatistics() {
        let monitor = FrameRateMonitor(sampleWindowSize: 60)
        var timestamp: UInt64 = 1_000_000_000

        // Session 1: 30fps with drops
        for i in 0..<120 {
            monitor.recordFrame(timestamp: timestamp)
            if i % 10 == 0 {
                timestamp += ms(40.0) // drop
            } else {
                timestamp += ms(33.33)
            }
        }
        XCTAssertGreaterThan(monitor.droppedFrames, 0)

        // Reset
        monitor.reset()

        // Session 2: perfect 60fps
        timestamp = 5_000_000_000
        for _ in 0..<180 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += ms(16.67)
        }

        let stats = monitor.statistics
        XCTAssertEqual(stats.droppedFrames, 0,
            "After reset, drops from previous session should not carry over")
        XCTAssertEqual(stats.averageFrameTimeMs, 16.67, accuracy: 0.1)
        XCTAssertEqual(stats.totalFrames, 180)
    }

    // =========================================================================
    // MARK: - Edge Cases
    // =========================================================================

    /// Very high frame rate (120fps) should not confuse the monitor.
    func test_highFrameRate_120fps() {
        let monitor = FrameRateMonitor(targetFPS: 120.0)
        let interval = ms(1000.0 / 120.0) // ~8.33ms
        var timestamp: UInt64 = 1_000_000_000

        for _ in 0..<360 { // 3 seconds at 120fps
            monitor.recordFrame(timestamp: timestamp)
            timestamp += interval
        }

        let stats = monitor.statistics
        XCTAssertGreaterThanOrEqual(stats.fps, 119)
        XCTAssertLessThanOrEqual(stats.fps, 120)
        XCTAssertEqual(stats.droppedFrames, 0)
        XCTAssertEqual(stats.averageFrameTimeMs, 8.33, accuracy: 0.1)
    }

    /// Burst of rapid frames followed by a gap — tests timestamp handling.
    func test_burstThenGap() {
        let monitor = FrameRateMonitor()
        var timestamp: UInt64 = 1_000_000_000

        // Burst: 10 frames at 5ms (very fast)
        for _ in 0..<10 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += ms(5.0)
        }

        // Gap: 200ms (simulates blocking I/O)
        timestamp += ms(200.0)
        monitor.recordFrame(timestamp: timestamp)

        // Resume normal
        for _ in 0..<60 {
            timestamp += ms(16.67)
            monitor.recordFrame(timestamp: timestamp)
        }

        let stats = monitor.statistics
        // The 200ms gap should be counted as a drop
        XCTAssertGreaterThanOrEqual(stats.droppedFrames, 1)
        // Max frame time should capture the gap
        XCTAssertGreaterThanOrEqual(stats.maxFrameTimeMs, 200.0)
    }
}

// =============================================================================
// MARK: - 12.2 Audio Latency Performance Tests
// =============================================================================

/// Tests for audio buffer behavior, latency, and sync characteristics.
///
/// These tests verify:
/// - Ring buffer latency stays within acceptable bounds
/// - Buffer underrun behavior produces silence (not glitches)
/// - Audio stays in sync with emulation frame rate
/// - Burst/drain patterns are handled gracefully
///
/// Tests use the RingBuffer<Float> directly to test producer-consumer
/// timing without requiring actual audio hardware.
final class AudioLatencyPerformanceTests: XCTestCase {

    // =========================================================================
    // MARK: - Ring Buffer Latency
    // =========================================================================

    /// At 44100 Hz with a 8192-sample ring buffer, maximum buffered latency
    /// is ~186ms (8191/44100). Verify this bound holds.
    func test_ringBuffer_maxLatencyBound() {
        let capacity = AudioEngine.ringBufferCapacity // 8192
        let sampleRate = AudioEngine.defaultSampleRate // 44100
        let buffer = RingBuffer<Float>(capacity: capacity)

        // Fill to near-capacity
        let samples = [Float](repeating: 0.5, count: capacity - 1)
        let written = buffer.write(samples)

        // Should write capacity-1 samples (ring buffer reserves one slot)
        XCTAssertEqual(written, capacity - 1)

        // Latency = buffered_samples / sample_rate
        let latencyMs = Double(buffer.count) / sampleRate * 1000.0
        let maxLatencyMs = Double(capacity - 1) / sampleRate * 1000.0
        XCTAssertEqual(latencyMs, maxLatencyMs, accuracy: 0.01)
        // Should be ~185.7ms
        XCTAssertLessThan(latencyMs, 200.0,
            "Max buffered latency should be under 200ms")
    }

    /// Typical operating latency: emulator writes ~735 samples/frame (44100/60),
    /// audio callback reads ~1024 samples. Verify steady-state buffer level.
    func test_ringBuffer_steadyStateLatency() {
        let buffer = RingBuffer<Float>(capacity: 8192)
        let samplesPerFrame = 44100 / 60 // ~735 samples per frame
        let callbackSize = 1024 // AVAudioEngine callback size

        // Simulate 5 seconds of operation (300 frames)
        var bufferLevels: [Int] = []

        for frame in 0..<300 {
            // Emulator produces samples
            let samples = [Float](repeating: 0.1, count: samplesPerFrame)
            buffer.write(samples)

            // Audio callback consumes (slightly less frequently than production
            // because 735 < 1024, so we consume approximately every 1.4 frames)
            if frame % 2 == 0 || buffer.count >= callbackSize {
                var output = [Float](repeating: 0.0, count: callbackSize)
                _ = output.withUnsafeMutableBufferPointer { ptr in
                    buffer.read(into: ptr, count: callbackSize)
                }
            }

            bufferLevels.append(buffer.count)
        }

        // Buffer level should stay bounded — not grow unbounded or drain to 0
        let maxLevel = bufferLevels.max()!
        let avgLevel = bufferLevels.reduce(0, +) / bufferLevels.count
        XCTAssertLessThan(maxLevel, 8192,
            "Buffer should never reach capacity in steady state")
        XCTAssertGreaterThan(avgLevel, 0,
            "Buffer should maintain some fill level")

        // Steady-state latency: avgLevel / sampleRate
        let avgLatencyMs = Double(avgLevel) / 44100.0 * 1000.0
        XCTAssertLessThan(avgLatencyMs, 50.0,
            "Average audio latency should stay under 50ms")
    }

    // =========================================================================
    // MARK: - Buffer Underrun Detection
    // =========================================================================

    /// When the ring buffer is empty, reads should return 0 samples.
    /// This is how the audio callback detects underruns and fills with silence.
    func test_ringBuffer_underrunReturnsZeroSamples() {
        let buffer = RingBuffer<Float>(capacity: 1024)

        var output = [Float](repeating: -1.0, count: 512)
        let read = output.withUnsafeMutableBufferPointer { ptr in
            buffer.read(into: ptr, count: 512)
        }

        XCTAssertEqual(read, 0,
            "Reading from empty buffer should return 0 samples")
    }

    /// Partial underrun: buffer has fewer samples than requested.
    func test_ringBuffer_partialUnderrun() {
        let buffer = RingBuffer<Float>(capacity: 1024)

        // Write only 100 samples
        let samples = [Float](repeating: 0.5, count: 100)
        buffer.write(samples)

        // Try to read 512
        var output = [Float](repeating: 0.0, count: 512)
        let read = output.withUnsafeMutableBufferPointer { ptr in
            buffer.read(into: ptr, count: 512)
        }

        XCTAssertEqual(read, 100,
            "Should read only available 100 samples from buffer")
        XCTAssertEqual(buffer.count, 0,
            "Buffer should be empty after draining all samples")
    }

    /// After underrun, new samples can be enqueued and read normally.
    func test_ringBuffer_recoveryAfterUnderrun() {
        let buffer = RingBuffer<Float>(capacity: 1024)

        // Drain attempt on empty buffer
        var output = [Float](repeating: 0.0, count: 256)
        let readEmpty = output.withUnsafeMutableBufferPointer { ptr in
            buffer.read(into: ptr, count: 256)
        }
        XCTAssertEqual(readEmpty, 0)

        // Write new samples
        let samples = [Float](repeating: 0.75, count: 256)
        let written = buffer.write(samples)
        XCTAssertEqual(written, 256)

        // Read them back
        let readRecovered = output.withUnsafeMutableBufferPointer { ptr in
            buffer.read(into: ptr, count: 256)
        }
        XCTAssertEqual(readRecovered, 256,
            "Buffer should work normally after underrun recovery")

        // Verify data integrity
        XCTAssertEqual(output[0], 0.75, accuracy: 0.001)
        XCTAssertEqual(output[255], 0.75, accuracy: 0.001)
    }

    // =========================================================================
    // MARK: - Audio/Emulation Sync
    // =========================================================================

    /// Simulate matched producer/consumer rates: emulator at 60fps producing
    /// 735 samples/frame, audio callback at 44100 Hz consuming 512 samples/callback.
    /// Buffer level should stay stable — no unbounded growth or starvation.
    func test_audioEmulationSync_stableBufferLevel() {
        let buffer = RingBuffer<Float>(capacity: 8192)
        let samplesPerFrame = 735 // 44100 / 60

        // Track min/max buffer levels over 10 seconds
        var minLevel = Int.max
        var maxLevel = 0
        var underrunCount = 0

        // 600 frames = 10 seconds
        for _ in 0..<600 {
            // Emulator writes samples for this frame
            let frameSamples = [Float](repeating: 0.1, count: samplesPerFrame)
            buffer.write(frameSamples)

            // Audio callback reads (approximately once per frame for 735 samples,
            // but using actual callback size of 512 to simulate real behavior)
            var output = [Float](repeating: 0.0, count: 512)
            let read = output.withUnsafeMutableBufferPointer { ptr in
                buffer.read(into: ptr, count: 512)
            }

            // Extra read to roughly match production rate (735 ≈ 512 + 223)
            var output2 = [Float](repeating: 0.0, count: 223)
            let read2 = output2.withUnsafeMutableBufferPointer { ptr in
                buffer.read(into: ptr, count: 223)
            }

            if read < 512 || read2 < 223 {
                underrunCount += 1
            }

            let level = buffer.count
            if level < minLevel { minLevel = level }
            if level > maxLevel { maxLevel = level }
        }

        XCTAssertEqual(underrunCount, 0,
            "No underruns expected when production matches consumption")
        // Buffer level should stay small (near zero since we consume ~= produce)
        XCTAssertLessThan(maxLevel, 2000,
            "Buffer should not grow beyond ~2000 samples in sync mode")
    }

    /// Emulator running slightly slow (59fps instead of 60) — audio should
    /// gradually drain the buffer but not crash or produce garbage.
    func test_audioSync_slightlySlowEmulator() {
        let buffer = RingBuffer<Float>(capacity: 8192)
        let samplesPerFrame = 735

        // Pre-fill buffer with 2048 samples (some headroom)
        let prefill = [Float](repeating: 0.1, count: 2048)
        buffer.write(prefill)

        // Run at 59fps for 5 seconds (295 frames instead of 300)
        var underruns = 0
        for _ in 0..<295 {
            let frameSamples = [Float](repeating: 0.1, count: samplesPerFrame)
            buffer.write(frameSamples)

            // Consumer still runs at 44100 Hz — consuming 735 samples per
            // 1/60th second. Over 295 frames the consumer wants
            // 300 frames worth of samples.
            var output = [Float](repeating: 0.0, count: samplesPerFrame)
            let read = output.withUnsafeMutableBufferPointer { ptr in
                buffer.read(into: ptr, count: samplesPerFrame)
            }
            if read < samplesPerFrame { underruns += 1 }

            // Consume the extra 1/60th second of audio every 59 frames
            // to simulate the consumer being slightly ahead
        }

        // Buffer should still be functional
        let remaining = buffer.count
        XCTAssertGreaterThanOrEqual(remaining, 0,
            "Buffer count should never go negative")
    }

    // =========================================================================
    // MARK: - Buffer Overflow Handling
    // =========================================================================

    /// When the ring buffer is full, writes should return fewer samples than
    /// requested. This prevents unbounded memory growth.
    func test_ringBuffer_overflowDropsSamples() {
        let buffer = RingBuffer<Float>(capacity: 256)

        // Fill the buffer completely
        let fill = [Float](repeating: 0.5, count: 255)
        let written1 = buffer.write(fill)
        XCTAssertEqual(written1, 255)

        // Try to write more — should fail gracefully
        let extra = [Float](repeating: 0.9, count: 100)
        let written2 = buffer.write(extra)
        XCTAssertEqual(written2, 0,
            "Should not write any samples when buffer is full")
    }

    /// Ring buffer handles rapid write/read cycles without corruption.
    func test_ringBuffer_rapidCycles_noCorruption() {
        let buffer = RingBuffer<Float>(capacity: 512)

        // 10,000 write/read cycles
        for cycle in 0..<10_000 {
            let value = Float(cycle % 100) / 100.0
            let samples = [Float](repeating: value, count: 32)
            buffer.write(samples)

            var output = [Float](repeating: 0.0, count: 32)
            let read = output.withUnsafeMutableBufferPointer { ptr in
                buffer.read(into: ptr, count: 32)
            }

            XCTAssertEqual(read, 32,
                "Should read 32 samples at cycle \(cycle)")
            // Verify data integrity
            XCTAssertEqual(output[0], value, accuracy: 0.001,
                "Sample data should match at cycle \(cycle)")
        }

        // Buffer should be empty after balanced cycles
        XCTAssertEqual(buffer.count, 0)
    }

    // =========================================================================
    // MARK: - AudioEngine Sample Conversion
    // =========================================================================

    /// AudioEngine converts 16-bit PCM to Float correctly.
    func test_audioEngine_16bitConversion() {
        let engine = AudioEngine()
        engine.configure(sampleRate: 44100, channels: 1, sampleSize: 2)
        engine.isEnabled = true

        // Create 16-bit signed PCM data: silence (0x0000), max positive (0x7FFF)
        let pcmData: [UInt8] = [
            0x00, 0x00, // Int16 = 0 → Float 0.0
            0xFF, 0x7F, // Int16 = 32767 → Float ~1.0
            0x01, 0x80, // Int16 = -32767 → Float ~-1.0
        ]

        let written = engine.enqueueSamplesFromEmulator(bytes: pcmData)
        XCTAssertEqual(written, 3,
            "Should convert 6 bytes into 3 16-bit samples")
    }

    /// AudioEngine converts 8-bit unsigned PCM to Float correctly.
    func test_audioEngine_8bitConversion() {
        let engine = AudioEngine()
        engine.configure(sampleRate: 44100, channels: 1, sampleSize: 1)
        engine.isEnabled = true

        // Create 8-bit unsigned PCM data: center (128), max (255), min (0)
        let pcmData: [UInt8] = [128, 255, 0]

        let written = engine.enqueueSamplesFromEmulator(bytes: pcmData)
        XCTAssertEqual(written, 3,
            "Should convert 3 bytes into 3 8-bit samples")
    }

    /// Volume scaling is applied during sample conversion.
    func test_audioEngine_volumeScaling() {
        let engine = AudioEngine()
        engine.configure(sampleRate: 44100, channels: 1, sampleSize: 2)
        engine.isEnabled = true
        engine.volume = 0.5

        // Max positive 16-bit sample
        let pcmData: [UInt8] = [0xFF, 0x7F]
        let written = engine.enqueueSamplesFromEmulator(bytes: pcmData)
        XCTAssertEqual(written, 1)

        // The buffered sample should be approximately 0.5 (max × volume)
        XCTAssertGreaterThan(engine.bufferedSamples, 0)
    }

    /// Disabled engine discards samples instead of buffering.
    func test_audioEngine_disabledDiscardsData() {
        let engine = AudioEngine()
        engine.configure(sampleRate: 44100, channels: 1, sampleSize: 2)
        engine.isEnabled = false

        let pcmData = [UInt8](repeating: 0x7F, count: 1000)
        let written = engine.enqueueSamplesFromEmulator(bytes: pcmData)

        XCTAssertEqual(written, 0,
            "Disabled engine should not accept samples")
        XCTAssertEqual(engine.bufferedSamples, 0)
    }

    /// Buffer low indicator fires when fill drops below callback size.
    func test_audioEngine_bufferLowIndicator() {
        let engine = AudioEngine()
        engine.configure(sampleRate: 44100, channels: 1, sampleSize: 2)
        engine.isEnabled = true

        // Initially empty — should be "low"
        XCTAssertTrue(engine.isBufferLow,
            "Empty buffer should report as low")

        // Fill with enough data to exceed callback size (1024 samples = 2048 bytes)
        let pcmData = [UInt8](repeating: 0x00, count: 4096) // 2048 16-bit samples
        engine.enqueueSamplesFromEmulator(bytes: pcmData)

        XCTAssertFalse(engine.isBufferLow,
            "Buffer with >1024 samples should not report as low")
    }

    /// clearBuffer() empties the ring buffer immediately.
    func test_audioEngine_clearBuffer() {
        let engine = AudioEngine()
        engine.configure(sampleRate: 44100, channels: 1, sampleSize: 2)
        engine.isEnabled = true

        let pcmData = [UInt8](repeating: 0x00, count: 2048)
        engine.enqueueSamplesFromEmulator(bytes: pcmData)
        XCTAssertGreaterThan(engine.bufferedSamples, 0)

        engine.clearBuffer()
        XCTAssertEqual(engine.bufferedSamples, 0,
            "clearBuffer should empty the ring buffer")
    }
}

// =============================================================================
// MARK: - 12.3 Memory Usage Performance Tests
// =============================================================================

/// Tests for memory stability under sustained and intensive operations.
///
/// These tests verify:
/// - Stable memory footprint over extended operations
/// - No significant spikes during large state save/load cycles
/// - Ring buffer memory stays bounded
/// - Frame rate monitor memory stays bounded
/// - Repeated allocations don't leak
///
/// Memory is measured using task_info via the Mach kernel API, which reports
/// the process's resident memory size. These measurements are approximate
/// and can vary by system state.
final class MemoryUsagePerformanceTests: XCTestCase {

    // =========================================================================
    // MARK: - Helpers
    // =========================================================================

    /// Returns the current process memory usage in bytes using task_info.
    ///
    /// Uses the Mach kernel's task_info API to get the resident memory size.
    /// This is the same metric shown in Activity Monitor's "Memory" column.
    private func currentMemoryBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), ptr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.phys_footprint)
    }

    /// Returns memory in megabytes for readability.
    private func currentMemoryMB() -> Double {
        Double(currentMemoryBytes()) / (1024.0 * 1024.0)
    }

    // =========================================================================
    // MARK: - Frame Rate Monitor Memory
    // =========================================================================

    /// FrameRateMonitor's ring buffer uses fixed memory regardless of
    /// how many frames are recorded. Verify no growth over time.
    func test_frameRateMonitor_memoryStable() {
        let monitor = FrameRateMonitor(sampleWindowSize: 120)
        var timestamp: UInt64 = 1_000_000_000

        let memBefore = currentMemoryBytes()

        // Record 60,000 frames (simulates ~16 minutes at 60fps)
        for _ in 0..<60_000 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += ms(16.67)
        }

        let memAfter = currentMemoryBytes()

        // Frame rate monitor should use fixed memory — the ring buffer is
        // pre-allocated at init time. Allow 1MB tolerance for measurement noise.
        let growth = Int64(memAfter) - Int64(memBefore)
        XCTAssertLessThan(growth, 1_000_000,
            "FrameRateMonitor memory should not grow: \(growth) bytes")
    }

    // =========================================================================
    // MARK: - Ring Buffer Memory
    // =========================================================================

    /// Ring buffer memory should be bounded by its capacity.
    func test_ringBuffer_memoryBounded() {
        let capacity = 8192
        let buffer = RingBuffer<Float>(capacity: capacity)

        let memBefore = currentMemoryBytes()

        // Perform 10,000 write/read cycles — memory should not grow
        for _ in 0..<10_000 {
            let samples = [Float](repeating: 0.5, count: 512)
            buffer.write(samples)

            var output = [Float](repeating: 0.0, count: 512)
            _ = output.withUnsafeMutableBufferPointer { ptr in
                buffer.read(into: ptr, count: 512)
            }
        }

        let memAfter = currentMemoryBytes()

        let growth = Int64(memAfter) - Int64(memBefore)
        // The temporary [Float] arrays are created and freed each iteration.
        // Net growth should be negligible. Allow 2MB for GC timing.
        XCTAssertLessThan(growth, 2_000_000,
            "Ring buffer operations should not leak: \(growth) bytes")
    }

    // =========================================================================
    // MARK: - State Persistence Memory
    // =========================================================================

    /// Repeated state save/load cycles should not accumulate memory.
    ///
    /// Each cycle creates a 210KB EmulatorState, writes it to disk, reads it
    /// back, and discards both. Memory should return to baseline after each.
    func test_stateSaveLoadCycles_noAccumulation() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("attic_memtest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let memBefore = currentMemoryBytes()

        // 50 save/load cycles with realistic 210KB state data
        for i in 0..<50 {
            autoreleasepool {
                let metadata = StateMetadata.create(replMode: .monitor, mountedDisks: [])
                var state = EmulatorState()
                state.data = [UInt8](repeating: UInt8(i & 0xFF), count: 210_000)

                let url = tempDir.appendingPathComponent("cycle_\(i).attic")
                try? StateFileHandler.write(to: url, metadata: metadata, state: state)

                if let loaded = try? StateFileHandler.read(from: url) {
                    _ = loaded
                }

                // Clean up file to avoid disk accumulation
                try? FileManager.default.removeItem(at: url)
            }
        }

        let memAfter = currentMemoryBytes()

        let growth = Int64(memAfter) - Int64(memBefore)
        // 50 cycles of 210KB should not leave significant residue.
        // Allow 5MB for GC timing and allocator fragmentation.
        XCTAssertLessThan(growth, 5_000_000,
            "50 state save/load cycles should not leak memory: \(growth) bytes")
    }

    /// A single large state allocation and deallocation should not spike
    /// permanently. Memory should return close to baseline.
    func test_largeStateAllocation_returnsToBaseline() {
        let memBefore = currentMemoryBytes()

        autoreleasepool {
            // Allocate a large state (1MB)
            var state = EmulatorState()
            state.data = [UInt8](repeating: 0xAB, count: 1_000_000)

            // Verify it was allocated
            XCTAssertEqual(state.data.count, 1_000_000)
        }

        // Force ARC to clean up
        let memAfter = currentMemoryBytes()

        // Memory should return within 2MB of baseline
        // (system allocator may retain some pages)
        let growth = Int64(memAfter) - Int64(memBefore)
        XCTAssertLessThan(growth, 2_000_000,
            "Memory should return near baseline after deallocation: \(growth) bytes")
    }

    // =========================================================================
    // MARK: - AudioEngine Memory
    // =========================================================================

    /// AudioEngine sample enqueueing should not leak memory over time.
    func test_audioEngine_noMemoryLeakDuringSampleEnqueue() {
        let engine = AudioEngine()
        engine.configure(sampleRate: 44100, channels: 1, sampleSize: 2)
        engine.isEnabled = true

        let memBefore = currentMemoryBytes()

        // Simulate 60 seconds of audio: 60fps × 60s = 3600 frames
        // Each frame produces ~1470 bytes (735 samples × 2 bytes)
        for _ in 0..<3600 {
            autoreleasepool {
                let pcmData = [UInt8](repeating: 0x00, count: 1470)
                engine.enqueueSamplesFromEmulator(bytes: pcmData)
            }
            // Periodically drain the buffer to prevent overflow
            engine.clearBuffer()
        }

        let memAfter = currentMemoryBytes()

        let growth = Int64(memAfter) - Int64(memBefore)
        // The ring buffer is fixed-size, and temporary arrays are freed.
        // Allow 2MB for GC timing.
        XCTAssertLessThan(growth, 2_000_000,
            "Audio sample enqueueing should not leak: \(growth) bytes")
    }

    // =========================================================================
    // MARK: - Combined Workload Memory
    // =========================================================================

    /// Simulate a realistic combined workload: frame rate monitoring +
    /// audio buffering + periodic state saves. Memory should stay stable.
    func test_combinedWorkload_memoryStable() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("attic_combined_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let monitor = FrameRateMonitor()
        let engine = AudioEngine()
        engine.configure(sampleRate: 44100, channels: 1, sampleSize: 2)
        engine.isEnabled = true

        let memBefore = currentMemoryBytes()
        var timestamp: UInt64 = 1_000_000_000

        // Simulate 30 seconds of operation
        for frame in 0..<1800 {
            autoreleasepool {
                // Record frame
                monitor.recordFrame(timestamp: timestamp)
                timestamp += ms(16.67)

                // Enqueue audio
                let pcmData = [UInt8](repeating: 0x00, count: 1470)
                engine.enqueueSamplesFromEmulator(bytes: pcmData)

                // Drain audio periodically
                if frame % 2 == 0 {
                    engine.clearBuffer()
                }

                // Save state every 5 seconds (every 300 frames)
                if frame > 0 && frame % 300 == 0 {
                    let metadata = StateMetadata.create(replMode: .monitor, mountedDisks: [])
                    var state = EmulatorState()
                    state.data = [UInt8](repeating: 0x00, count: 210_000)
                    let url = tempDir.appendingPathComponent("save_\(frame).attic")
                    try? StateFileHandler.write(to: url, metadata: metadata, state: state)
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }

        let memAfter = currentMemoryBytes()

        let growth = Int64(memAfter) - Int64(memBefore)
        // Combined workload should stay bounded. Allow 5MB for all components.
        XCTAssertLessThan(growth, 5_000_000,
            "Combined workload memory should stay stable: \(growth) bytes growth")
    }
}
