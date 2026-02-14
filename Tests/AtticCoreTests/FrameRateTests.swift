// =============================================================================
// FrameRateTests.swift - Frame Rate Monitor Unit Tests
// =============================================================================
//
// Tests for FrameRateMonitor, verifying:
// - FPS calculation accuracy
// - Frame drop detection at various thresholds
// - Statistics computation (average, min, max, jitter)
// - Ring buffer behavior when the sample window fills
// - Reset functionality
// - Edge cases (single frame, zero frames, burst patterns)
//
// These tests use explicit timestamps (nanoseconds) injected via
// recordFrame(timestamp:) so that timing is deterministic — no dependency
// on wall-clock precision or Metal rendering.
//
// Run with: swift test --filter FrameRateTests
//
// =============================================================================

import XCTest
@testable import AtticCore

// =============================================================================
// MARK: - Helpers
// =============================================================================

/// Converts milliseconds to nanoseconds for timestamp injection.
private func ms(_ milliseconds: Double) -> UInt64 {
    return UInt64(milliseconds * 1_000_000.0)
}

// =============================================================================
// MARK: - Initialization Tests
// =============================================================================

final class FrameRateMonitorInitTests: XCTestCase {

    /// Verify default configuration values.
    func test_defaultInit() {
        let monitor = FrameRateMonitor()

        XCTAssertEqual(monitor.targetFPS, 60.0)
        XCTAssertEqual(monitor.targetFrameTimeMs, 1000.0 / 60.0, accuracy: 0.01)
        XCTAssertEqual(monitor.dropThresholdMultiplier, 1.5)
        // 60fps target = 16.67ms, × 1.5 = 25.0ms threshold
        XCTAssertEqual(monitor.dropThresholdMs, 25.0, accuracy: 0.1)
        XCTAssertEqual(monitor.sampleWindowSize, 120)
        XCTAssertEqual(monitor.currentFPS, 0)
        XCTAssertEqual(monitor.totalFrames, 0)
        XCTAssertEqual(monitor.droppedFrames, 0)
    }

    /// Verify custom configuration.
    func test_customInit() {
        let monitor = FrameRateMonitor(
            targetFPS: 30.0,
            dropThresholdMultiplier: 2.0,
            sampleWindowSize: 60
        )

        XCTAssertEqual(monitor.targetFPS, 30.0)
        XCTAssertEqual(monitor.targetFrameTimeMs, 1000.0 / 30.0, accuracy: 0.01)
        XCTAssertEqual(monitor.dropThresholdMultiplier, 2.0)
        // 30fps = 33.33ms, × 2.0 = 66.67ms
        XCTAssertEqual(monitor.dropThresholdMs, 66.67, accuracy: 0.1)
        XCTAssertEqual(monitor.sampleWindowSize, 60)
    }
}

// =============================================================================
// MARK: - FPS Calculation Tests
// =============================================================================

final class FrameRateFPSTests: XCTestCase {

    /// Simulate perfect 60fps for 2 seconds and verify FPS reads 60.
    func test_perfect60fps() {
        let monitor = FrameRateMonitor()
        let frameIntervalNs = ms(1000.0 / 60.0) // ~16.67ms
        var timestamp: UInt64 = 1_000_000_000 // start at 1 second

        // Record 120 frames (2 seconds at 60fps)
        for _ in 0..<120 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += frameIntervalNs
        }

        // After >1 second, FPS should have been updated
        XCTAssertEqual(monitor.currentFPS, 60,
            "Expected 60 FPS for perfect 60fps frame pacing")
        XCTAssertEqual(monitor.totalFrames, 120)
        XCTAssertEqual(monitor.droppedFrames, 0,
            "No drops expected at perfect 60fps")
    }

    /// Simulate perfect 30fps and verify FPS reads 30.
    func test_perfect30fps() {
        let monitor = FrameRateMonitor(targetFPS: 30.0)
        let frameIntervalNs = ms(1000.0 / 30.0) // ~33.33ms
        var timestamp: UInt64 = 1_000_000_000

        for _ in 0..<60 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += frameIntervalNs
        }

        XCTAssertEqual(monitor.currentFPS, 30,
            "Expected 30 FPS for perfect 30fps frame pacing")
        XCTAssertEqual(monitor.droppedFrames, 0)
    }

    /// FPS should not update until at least 1 second has elapsed.
    func test_fpsNotUpdatedBeforeOneSecond() {
        let monitor = FrameRateMonitor()
        let frameIntervalNs = ms(16.67)
        var timestamp: UInt64 = 1_000_000_000

        // Record only 30 frames (~0.5 seconds)
        for _ in 0..<30 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += frameIntervalNs
        }

        // FPS should still be 0 since we haven't reached 1 second yet
        XCTAssertEqual(monitor.currentFPS, 0,
            "FPS should not update before 1 second has passed")
    }

    /// Verify FPS updates correctly across multiple 1-second windows.
    func test_fpsUpdatesAcrossWindows() {
        let monitor = FrameRateMonitor()
        var timestamp: UInt64 = 1_000_000_000

        // First second: 60fps
        for _ in 0..<61 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += ms(16.67)
        }
        XCTAssertEqual(monitor.currentFPS, 60)

        // Second second: 30fps (double interval)
        for _ in 0..<31 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += ms(33.33)
        }
        XCTAssertEqual(monitor.currentFPS, 30,
            "FPS should update to 30 when frame rate drops")
    }
}

// =============================================================================
// MARK: - Frame Drop Detection Tests
// =============================================================================

final class FrameRateDropTests: XCTestCase {

    /// A single frame that exceeds the drop threshold should be counted.
    func test_singleDrop() {
        let monitor = FrameRateMonitor() // threshold = 25ms
        var timestamp: UInt64 = 1_000_000_000

        // 10 normal frames
        for _ in 0..<10 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += ms(16.67)
        }

        // One dropped frame (30ms > 25ms threshold)
        monitor.recordFrame(timestamp: timestamp)
        timestamp += ms(30.0)
        monitor.recordFrame(timestamp: timestamp)

        XCTAssertEqual(monitor.droppedFrames, 1,
            "One frame at 30ms should count as a drop (threshold 25ms)")
    }

    /// Multiple drops interspersed with normal frames.
    func test_multipleDrops() {
        let monitor = FrameRateMonitor()
        var timestamp: UInt64 = 1_000_000_000

        // Pattern: 5 normal, 1 drop, 5 normal, 1 drop, 5 normal
        for _ in 0..<5 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += ms(16.67)
        }
        // Drop 1: 40ms
        monitor.recordFrame(timestamp: timestamp)
        timestamp += ms(40.0)
        monitor.recordFrame(timestamp: timestamp)

        for _ in 0..<4 {
            timestamp += ms(16.67)
            monitor.recordFrame(timestamp: timestamp)
        }
        // Drop 2: 50ms
        timestamp += ms(50.0)
        monitor.recordFrame(timestamp: timestamp)

        for _ in 0..<4 {
            timestamp += ms(16.67)
            monitor.recordFrame(timestamp: timestamp)
        }

        XCTAssertEqual(monitor.droppedFrames, 2,
            "Should detect exactly 2 dropped frames")
    }

    /// A frame exactly at the threshold should NOT count as dropped.
    func test_frameAtThresholdNotDropped() {
        let monitor = FrameRateMonitor() // threshold = 25.0ms
        var timestamp: UInt64 = 1_000_000_000

        monitor.recordFrame(timestamp: timestamp)
        timestamp += ms(25.0) // exactly at threshold
        monitor.recordFrame(timestamp: timestamp)

        XCTAssertEqual(monitor.droppedFrames, 0,
            "Frame exactly at threshold should not be counted as dropped")
    }

    /// A frame just above the threshold should be counted as dropped.
    func test_frameAboveThresholdDropped() {
        let monitor = FrameRateMonitor()
        var timestamp: UInt64 = 1_000_000_000

        monitor.recordFrame(timestamp: timestamp)
        timestamp += ms(25.1) // just above 25ms
        monitor.recordFrame(timestamp: timestamp)

        XCTAssertEqual(monitor.droppedFrames, 1,
            "Frame just above threshold should count as dropped")
    }

    /// No drops when all frames are within the target interval.
    func test_noDropsAtPerfectRate() {
        let monitor = FrameRateMonitor()
        var timestamp: UInt64 = 1_000_000_000

        for _ in 0..<200 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += ms(16.67)
        }

        XCTAssertEqual(monitor.droppedFrames, 0,
            "No drops expected when all frames are at target interval")
    }

    /// Custom drop threshold multiplier should affect detection.
    func test_customDropThreshold() {
        // With 2.0× threshold at 60fps, drop threshold = 33.33ms
        let monitor = FrameRateMonitor(dropThresholdMultiplier: 2.0)
        var timestamp: UInt64 = 1_000_000_000

        monitor.recordFrame(timestamp: timestamp)
        // 30ms is above default 1.5× threshold (25ms) but below 2.0× (33.33ms)
        timestamp += ms(30.0)
        monitor.recordFrame(timestamp: timestamp)

        XCTAssertEqual(monitor.droppedFrames, 0,
            "30ms should not be a drop with 2.0× threshold (33.33ms)")

        // 35ms exceeds 2.0× threshold
        timestamp += ms(35.0)
        monitor.recordFrame(timestamp: timestamp)

        XCTAssertEqual(monitor.droppedFrames, 1,
            "35ms should be a drop with 2.0× threshold (33.33ms)")
    }
}

// =============================================================================
// MARK: - Statistics Tests
// =============================================================================

final class FrameRateStatisticsTests: XCTestCase {

    /// Statistics on zero frames should return zeroes.
    func test_emptyStatistics() {
        let monitor = FrameRateMonitor()
        let stats = monitor.statistics

        XCTAssertEqual(stats.totalFrames, 0)
        XCTAssertEqual(stats.droppedFrames, 0)
        XCTAssertEqual(stats.averageFrameTimeMs, 0)
        XCTAssertEqual(stats.minFrameTimeMs, 0)
        XCTAssertEqual(stats.maxFrameTimeMs, 0)
        XCTAssertEqual(stats.jitterMs, 0)
        XCTAssertEqual(stats.consistencyPercent, 100.0)
    }

    /// Statistics after only one frame (no intervals recorded).
    func test_singleFrameStatistics() {
        let monitor = FrameRateMonitor()
        monitor.recordFrame(timestamp: 1_000_000_000)
        let stats = monitor.statistics

        XCTAssertEqual(stats.totalFrames, 1)
        XCTAssertEqual(stats.droppedFrames, 0)
        // No intervals yet, so timing stats are zero
        XCTAssertEqual(stats.averageFrameTimeMs, 0)
    }

    /// Average frame time for perfect 60fps should be ~16.67ms.
    func test_averageFrameTime_perfect60fps() {
        let monitor = FrameRateMonitor(sampleWindowSize: 10)
        var timestamp: UInt64 = 1_000_000_000

        for _ in 0..<11 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += ms(16.67)
        }

        let stats = monitor.statistics
        XCTAssertEqual(stats.averageFrameTimeMs, 16.67, accuracy: 0.01,
            "Average frame time should be ~16.67ms at 60fps")
    }

    /// Min and max should reflect the actual range of frame times.
    func test_minMaxFrameTime() {
        let monitor = FrameRateMonitor(sampleWindowSize: 20)
        var timestamp: UInt64 = 1_000_000_000

        // First frame (baseline)
        monitor.recordFrame(timestamp: timestamp)

        // 5 frames at 15ms
        for _ in 0..<5 {
            timestamp += ms(15.0)
            monitor.recordFrame(timestamp: timestamp)
        }

        // 5 frames at 20ms
        for _ in 0..<5 {
            timestamp += ms(20.0)
            monitor.recordFrame(timestamp: timestamp)
        }

        let stats = monitor.statistics
        XCTAssertEqual(stats.minFrameTimeMs, 15.0, accuracy: 0.01)
        XCTAssertEqual(stats.maxFrameTimeMs, 20.0, accuracy: 0.01)
    }

    /// Jitter should be zero for perfectly consistent frames.
    func test_zeroJitter() {
        let monitor = FrameRateMonitor(sampleWindowSize: 10)
        var timestamp: UInt64 = 1_000_000_000

        for _ in 0..<11 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += ms(16.67)
        }

        let stats = monitor.statistics
        XCTAssertEqual(stats.jitterMs, 0.0, accuracy: 0.01,
            "Jitter should be ~0 for perfectly consistent frame pacing")
    }

    /// Jitter should be non-zero when frame times vary.
    func test_nonZeroJitter() {
        let monitor = FrameRateMonitor(sampleWindowSize: 20)
        var timestamp: UInt64 = 1_000_000_000

        monitor.recordFrame(timestamp: timestamp)

        // Alternating 10ms and 20ms intervals
        for i in 0..<10 {
            let interval = (i % 2 == 0) ? 10.0 : 20.0
            timestamp += ms(interval)
            monitor.recordFrame(timestamp: timestamp)
        }

        let stats = monitor.statistics
        XCTAssertGreaterThan(stats.jitterMs, 1.0,
            "Jitter should be significant for alternating 10ms/20ms frames")
    }

    /// Consistency percentage: 100% when no drops, lower when drops occur.
    func test_consistencyPercent() {
        let monitor = FrameRateMonitor(sampleWindowSize: 20)
        var timestamp: UInt64 = 1_000_000_000

        // 10 normal frames
        for _ in 0..<10 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += ms(16.67)
        }

        let statsNoDrops = monitor.statistics
        XCTAssertEqual(statsNoDrops.consistencyPercent, 100.0, accuracy: 0.1)

        // Add 1 dropped frame (30ms)
        timestamp += ms(30.0)
        monitor.recordFrame(timestamp: timestamp)

        let statsOneDrop = monitor.statistics
        // 11 total, 1 drop = 10/11 ≈ 90.9%
        XCTAssertEqual(statsOneDrop.consistencyPercent, 90.9, accuracy: 0.5)
    }

    /// Statistics should include the configured thresholds.
    func test_statisticsIncludeThresholds() {
        let monitor = FrameRateMonitor(targetFPS: 60.0, dropThresholdMultiplier: 1.5)
        let stats = monitor.statistics

        XCTAssertEqual(stats.targetFrameTimeMs, 1000.0 / 60.0, accuracy: 0.01)
        XCTAssertEqual(stats.dropThresholdMs, 25.0, accuracy: 0.1)
    }
}

// =============================================================================
// MARK: - Ring Buffer Tests
// =============================================================================

final class FrameRateRingBufferTests: XCTestCase {

    /// When more frames than sampleWindowSize are recorded, oldest are replaced.
    func test_ringBufferOverwrite() {
        let windowSize = 5
        let monitor = FrameRateMonitor(sampleWindowSize: windowSize)
        var timestamp: UInt64 = 1_000_000_000

        // First frame (baseline)
        monitor.recordFrame(timestamp: timestamp)

        // 5 frames at 10ms (fills the window)
        for _ in 0..<5 {
            timestamp += ms(10.0)
            monitor.recordFrame(timestamp: timestamp)
        }

        // Now add 5 frames at 20ms (overwrites the 10ms entries)
        for _ in 0..<5 {
            timestamp += ms(20.0)
            monitor.recordFrame(timestamp: timestamp)
        }

        let stats = monitor.statistics
        // All 10ms entries should be overwritten — average should be 20ms
        XCTAssertEqual(stats.averageFrameTimeMs, 20.0, accuracy: 0.01,
            "After ring buffer wraps, old entries should be replaced")
        XCTAssertEqual(stats.minFrameTimeMs, 20.0, accuracy: 0.01)
        XCTAssertEqual(stats.maxFrameTimeMs, 20.0, accuracy: 0.01)
    }

    /// Total frame count should be cumulative, not limited by window size.
    func test_totalFramesExceedWindowSize() {
        let monitor = FrameRateMonitor(sampleWindowSize: 5)
        var timestamp: UInt64 = 1_000_000_000

        for _ in 0..<20 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += ms(16.67)
        }

        XCTAssertEqual(monitor.totalFrames, 20,
            "Total frames should count all frames, not be limited by window")
    }
}

// =============================================================================
// MARK: - Reset Tests
// =============================================================================

final class FrameRateResetTests: XCTestCase {

    /// After reset, all counters and statistics should be zero.
    func test_resetClearsAll() {
        let monitor = FrameRateMonitor()
        var timestamp: UInt64 = 1_000_000_000

        // Record some frames including drops
        for _ in 0..<100 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += ms(16.67)
        }
        timestamp += ms(50.0) // dropped frame
        monitor.recordFrame(timestamp: timestamp)

        // Verify we have data
        XCTAssertGreaterThan(monitor.totalFrames, 0)
        XCTAssertGreaterThan(monitor.droppedFrames, 0)

        // Reset
        monitor.reset()

        XCTAssertEqual(monitor.totalFrames, 0)
        XCTAssertEqual(monitor.droppedFrames, 0)
        XCTAssertEqual(monitor.currentFPS, 0)

        let stats = monitor.statistics
        XCTAssertEqual(stats.averageFrameTimeMs, 0)
        XCTAssertEqual(stats.totalFrames, 0)
        XCTAssertEqual(stats.droppedFrames, 0)
    }

    /// After reset, recording resumes correctly from a new baseline.
    func test_resetThenResume() {
        let monitor = FrameRateMonitor(sampleWindowSize: 10)
        var timestamp: UInt64 = 1_000_000_000

        // Record 5 frames at 10ms
        for _ in 0..<6 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += ms(10.0)
        }

        monitor.reset()

        // Record 5 frames at 20ms
        timestamp = 2_000_000_000
        for _ in 0..<6 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += ms(20.0)
        }

        let stats = monitor.statistics
        XCTAssertEqual(stats.averageFrameTimeMs, 20.0, accuracy: 0.01,
            "After reset, statistics should reflect only new frames")
        XCTAssertEqual(stats.totalFrames, 6)
    }
}

// =============================================================================
// MARK: - Simulated 60fps Sustained Test
// =============================================================================

final class FrameRateSustainedTests: XCTestCase {

    /// Simulate 5 seconds of 60fps and verify no drops and consistent FPS.
    ///
    /// This is the primary test for the "maintains 60fps, no frame drops"
    /// requirement (attic-69h.1).
    ///
    /// Note: FPS is calculated as Int(frameCount / elapsedSeconds) which can
    /// report 59 instead of 60 due to truncation. We accept 59-60 as valid.
    func test_sustained60fps_noDrops() {
        let monitor = FrameRateMonitor()
        let frameIntervalNs = ms(16.6667) // 60fps
        var timestamp: UInt64 = 1_000_000_000

        // 5 seconds × 60fps = 300 frames
        for _ in 0..<300 {
            monitor.recordFrame(timestamp: timestamp)
            timestamp += frameIntervalNs
        }

        let stats = monitor.statistics

        // FPS should be 59-60 (truncation of ~59.99 can yield 59)
        XCTAssertGreaterThanOrEqual(stats.fps, 59,
            "FPS should be at least 59 for perfect 60fps pacing")
        XCTAssertLessThanOrEqual(stats.fps, 60,
            "FPS should not exceed 60")

        // No dropped frames
        XCTAssertEqual(stats.droppedFrames, 0,
            "No frames should be dropped at perfect 60fps")

        // Average frame time should be ~16.67ms
        XCTAssertEqual(stats.averageFrameTimeMs, 16.67, accuracy: 0.1)

        // Jitter should be essentially zero
        XCTAssertEqual(stats.jitterMs, 0.0, accuracy: 0.01)

        // 100% consistency
        XCTAssertEqual(stats.consistencyPercent, 100.0, accuracy: 0.01)
    }

    /// Simulate 60fps with realistic jitter (±1ms) — should still be no drops.
    func test_sustained60fps_withMinorJitter() {
        let monitor = FrameRateMonitor()
        var timestamp: UInt64 = 1_000_000_000

        // Use a deterministic pseudo-random jitter pattern
        // Frame intervals: 16.67ms ± up to 2ms, always within 25ms threshold
        let jitterPattern: [Double] = [
            16.0, 17.3, 16.2, 17.1, 16.8, 15.9, 17.4, 16.5, 16.9, 16.1,
            17.0, 16.3, 17.2, 16.6, 16.4, 15.8, 17.5, 16.7, 16.0, 17.3
        ]

        // 300 frames (~5 seconds)
        for i in 0..<300 {
            monitor.recordFrame(timestamp: timestamp)
            let interval = jitterPattern[i % jitterPattern.count]
            timestamp += ms(interval)
        }

        let stats = monitor.statistics

        // Should still register ~60fps despite minor jitter
        XCTAssertGreaterThanOrEqual(stats.fps, 58,
            "FPS should be ~60 with minor jitter")
        XCTAssertLessThanOrEqual(stats.fps, 62)

        // No dropped frames — all intervals are well under 25ms
        XCTAssertEqual(stats.droppedFrames, 0,
            "Minor jitter (±2ms) should not cause drops")

        // Jitter should be small but non-zero
        XCTAssertGreaterThan(stats.jitterMs, 0.0)
        XCTAssertLessThan(stats.jitterMs, 2.0,
            "Jitter should be under 2ms for ±2ms variation")
    }

    /// Simulate a scenario with occasional drops and verify detection.
    ///
    /// A drop is detected when the NEXT frame arrives and measures the long
    /// interval, so we need a frame after the last stall to detect it.
    func test_sustained60fps_withOccasionalDrops() {
        let monitor = FrameRateMonitor()
        var timestamp: UInt64 = 1_000_000_000
        var expectedDrops = 0

        // 301 frames, with a stall every 50 frames.
        // The extra frame ensures the last stall is detected.
        for i in 0..<301 {
            monitor.recordFrame(timestamp: timestamp)
            if i > 0 && i % 50 == 0 {
                // Simulate a 40ms stall (garbage collection, system load, etc.)
                timestamp += ms(40.0)
                expectedDrops += 1
            } else {
                timestamp += ms(16.67)
            }
        }

        // Record one final frame to detect the last stall interval
        monitor.recordFrame(timestamp: timestamp)

        let stats = monitor.statistics

        XCTAssertEqual(stats.droppedFrames, expectedDrops,
            "Should detect exactly \(expectedDrops) drops")
        XCTAssertLessThan(stats.consistencyPercent, 100.0,
            "Consistency should be below 100% when drops occur")
        XCTAssertGreaterThan(stats.consistencyPercent, 95.0,
            "With only occasional drops, consistency should still be high")
    }
}

// =============================================================================
// MARK: - FPS Counter Accuracy Test (Legacy Logic)
// =============================================================================

final class FrameRateFPSCounterTests: XCTestCase {

    /// Verify that the FPS counter matches the actual frame delivery rate
    /// for various rates (30, 45, 60, 120).
    func test_fpsAccuracyAtVariousRates() {
        let rates: [Double] = [30.0, 45.0, 60.0, 120.0]

        for rate in rates {
            let monitor = FrameRateMonitor(targetFPS: rate)
            let intervalNs = ms(1000.0 / rate)
            var timestamp: UInt64 = 1_000_000_000

            // Run for 3 seconds to get a stable reading
            let frameCount = Int(rate * 3)
            for _ in 0..<frameCount {
                monitor.recordFrame(timestamp: timestamp)
                timestamp += intervalNs
            }

            XCTAssertEqual(monitor.currentFPS, Int(rate),
                "FPS should read \(Int(rate)) for \(rate)fps delivery")
        }
    }
}
