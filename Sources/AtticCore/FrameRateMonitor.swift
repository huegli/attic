// =============================================================================
// FrameRateMonitor.swift - Frame Rate Tracking and Drop Detection
// =============================================================================
//
// This file provides a frame rate monitor that tracks timing statistics for
// emulator display output. It measures:
//
// - Current FPS (frames per second), updated once per second
// - Frame drops: frames that took significantly longer than the target interval
// - Frame time statistics: min, max, average, and jitter
//
// The monitor is designed to be called once per rendered frame (typically from
// a Metal draw callback or emulation loop). It uses monotonic clock timestamps
// (mach_continuous_time) to avoid issues with wall-clock adjustments.
//
// Usage:
//
//     let monitor = FrameRateMonitor(targetFPS: 60)
//
//     // Call each frame:
//     monitor.recordFrame()
//
//     // Read current stats:
//     let stats = monitor.statistics
//     print("FPS: \(stats.fps), drops: \(stats.droppedFrames)")
//
// This class lives in AtticCore (not AtticGUI) so it can be unit-tested
// without requiring Metal or a display.
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - FrameRateStatistics
// =============================================================================

/// A snapshot of frame rate statistics over a measurement window.
///
/// All time values are in milliseconds. A "dropped frame" is one whose
/// interval exceeded `dropThresholdMs`.
public struct FrameRateStatistics: Sendable {
    /// Current frames per second (updated once per second).
    public let fps: Int

    /// Total number of frames recorded since the last reset.
    public let totalFrames: Int

    /// Number of frames that exceeded the drop threshold.
    public let droppedFrames: Int

    /// Average frame interval in milliseconds over the sample window.
    public let averageFrameTimeMs: Double

    /// Minimum frame interval in milliseconds over the sample window.
    public let minFrameTimeMs: Double

    /// Maximum frame interval in milliseconds over the sample window.
    public let maxFrameTimeMs: Double

    /// Standard deviation of frame intervals in milliseconds (measures jitter).
    /// Lower values indicate more consistent frame pacing.
    public let jitterMs: Double

    /// The drop threshold in milliseconds. Frames longer than this are "drops".
    public let dropThresholdMs: Double

    /// The target frame interval in milliseconds (e.g. 16.67 for 60fps).
    public let targetFrameTimeMs: Double

    /// Percentage of frames that were NOT dropped (0.0–100.0).
    public var consistencyPercent: Double {
        guard totalFrames > 0 else { return 100.0 }
        return Double(totalFrames - droppedFrames) / Double(totalFrames) * 100.0
    }
}

// =============================================================================
// MARK: - FrameRateMonitor
// =============================================================================

/// Tracks frame timing to detect drops and calculate FPS.
///
/// This class is **not** thread-safe — call all methods from the same thread
/// (typically the main/render thread). If you need cross-thread access, wrap
/// reads of `statistics` and `currentFPS` in appropriate synchronization.
///
/// The monitor uses `mach_continuous_time()` for monotonic timestamps that
/// are unaffected by system clock changes and continue ticking during sleep.
public class FrameRateMonitor {

    // =========================================================================
    // MARK: - Configuration
    // =========================================================================

    /// Target frames per second (e.g. 60).
    public let targetFPS: Double

    /// Target frame interval in milliseconds.
    public let targetFrameTimeMs: Double

    /// Multiplier of target frame time that counts as a "drop".
    /// For example, 1.5 means any frame taking longer than 25ms (at 60fps)
    /// is considered dropped.
    public let dropThresholdMultiplier: Double

    /// Drop threshold in milliseconds, derived from target and multiplier.
    public let dropThresholdMs: Double

    /// Number of recent frame intervals to keep for statistics.
    /// Defaults to 120 (2 seconds at 60fps).
    public let sampleWindowSize: Int

    // =========================================================================
    // MARK: - State
    // =========================================================================

    /// Timestamp of the previous frame (nanoseconds, monotonic clock).
    private var lastFrameTimestamp: UInt64 = 0

    /// Recent frame intervals in milliseconds (ring buffer).
    private var frameTimes: [Double]

    /// Current write position in the ring buffer.
    private var frameTimeIndex: Int = 0

    /// Number of valid entries in the ring buffer (up to sampleWindowSize).
    private var frameTimeCount: Int = 0

    /// Total frames recorded since last reset.
    private(set) public var totalFrames: Int = 0

    /// Total dropped frames since last reset.
    private(set) public var droppedFrames: Int = 0

    // FPS calculation (updated once per second).
    private var fpsFrameCount: Int = 0
    private var fpsLastUpdate: UInt64 = 0

    /// Current FPS value, updated approximately once per second.
    private(set) public var currentFPS: Int = 0

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a new frame rate monitor.
    ///
    /// - Parameters:
    ///   - targetFPS: Expected frame rate (default 60).
    ///   - dropThresholdMultiplier: How many times the target frame time a frame
    ///     must take to be considered "dropped" (default 1.5).
    ///   - sampleWindowSize: Number of recent frame intervals to keep for
    ///     statistics (default 120, i.e. 2 seconds at 60fps).
    public init(
        targetFPS: Double = 60.0,
        dropThresholdMultiplier: Double = 1.5,
        sampleWindowSize: Int = 120
    ) {
        self.targetFPS = targetFPS
        self.targetFrameTimeMs = 1000.0 / targetFPS
        self.dropThresholdMultiplier = dropThresholdMultiplier
        self.dropThresholdMs = (1000.0 / targetFPS) * dropThresholdMultiplier
        self.sampleWindowSize = sampleWindowSize
        self.frameTimes = [Double](repeating: 0.0, count: sampleWindowSize)
    }

    // =========================================================================
    // MARK: - Recording
    // =========================================================================

    /// Records a frame at the current time.
    ///
    /// Call this once per rendered frame (e.g. from MTKViewDelegate.draw()
    /// or the emulation loop). The first call establishes the baseline;
    /// statistics begin from the second call onward.
    public func recordFrame() {
        recordFrame(timestamp: currentTimestampNs())
    }

    /// Records a frame with an explicit timestamp (for testing).
    ///
    /// - Parameter timestamp: Monotonic timestamp in nanoseconds.
    public func recordFrame(timestamp: UInt64) {
        if lastFrameTimestamp == 0 {
            // First frame — establish baseline
            lastFrameTimestamp = timestamp
            fpsLastUpdate = timestamp
            totalFrames += 1
            fpsFrameCount += 1
            return
        }

        let elapsedNs = timestamp - lastFrameTimestamp
        let elapsedMs = Double(elapsedNs) / 1_000_000.0
        lastFrameTimestamp = timestamp

        // Store in ring buffer
        frameTimes[frameTimeIndex] = elapsedMs
        frameTimeIndex = (frameTimeIndex + 1) % sampleWindowSize
        if frameTimeCount < sampleWindowSize {
            frameTimeCount += 1
        }

        totalFrames += 1
        fpsFrameCount += 1

        // Detect drop
        if elapsedMs > dropThresholdMs {
            droppedFrames += 1
        }

        // Update FPS once per second
        let fpsElapsedNs = timestamp - fpsLastUpdate
        let fpsElapsedS = Double(fpsElapsedNs) / 1_000_000_000.0
        if fpsElapsedS >= 1.0 {
            currentFPS = Int(Double(fpsFrameCount) / fpsElapsedS)
            fpsFrameCount = 0
            fpsLastUpdate = timestamp
        }
    }

    // =========================================================================
    // MARK: - Statistics
    // =========================================================================

    /// Returns a snapshot of the current frame rate statistics.
    ///
    /// The statistics cover the most recent `sampleWindowSize` frames for
    /// timing metrics (average, min, max, jitter), and lifetime totals for
    /// frame count and drop count.
    public var statistics: FrameRateStatistics {
        guard frameTimeCount > 0 else {
            return FrameRateStatistics(
                fps: currentFPS,
                totalFrames: totalFrames,
                droppedFrames: droppedFrames,
                averageFrameTimeMs: 0,
                minFrameTimeMs: 0,
                maxFrameTimeMs: 0,
                jitterMs: 0,
                dropThresholdMs: dropThresholdMs,
                targetFrameTimeMs: targetFrameTimeMs
            )
        }

        var sum = 0.0
        var minTime = Double.greatestFiniteMagnitude
        var maxTime = 0.0

        for i in 0..<frameTimeCount {
            let t = frameTimes[i]
            sum += t
            if t < minTime { minTime = t }
            if t > maxTime { maxTime = t }
        }

        let avg = sum / Double(frameTimeCount)

        // Calculate standard deviation (jitter)
        var varianceSum = 0.0
        for i in 0..<frameTimeCount {
            let diff = frameTimes[i] - avg
            varianceSum += diff * diff
        }
        let jitter = (varianceSum / Double(frameTimeCount)).squareRoot()

        return FrameRateStatistics(
            fps: currentFPS,
            totalFrames: totalFrames,
            droppedFrames: droppedFrames,
            averageFrameTimeMs: avg,
            minFrameTimeMs: minTime,
            maxFrameTimeMs: maxTime,
            jitterMs: jitter,
            dropThresholdMs: dropThresholdMs,
            targetFrameTimeMs: targetFrameTimeMs
        )
    }

    // =========================================================================
    // MARK: - Reset
    // =========================================================================

    /// Resets all statistics and frame history.
    ///
    /// Call this when you want to start a fresh measurement window,
    /// for example after the emulator resumes from a pause.
    public func reset() {
        lastFrameTimestamp = 0
        frameTimeIndex = 0
        frameTimeCount = 0
        totalFrames = 0
        droppedFrames = 0
        fpsFrameCount = 0
        fpsLastUpdate = 0
        currentFPS = 0
        for i in 0..<sampleWindowSize {
            frameTimes[i] = 0.0
        }
    }

    // =========================================================================
    // MARK: - Private Helpers
    // =========================================================================

    /// Returns the current monotonic timestamp in nanoseconds.
    ///
    /// Uses `mach_continuous_time()` which provides a monotonic clock that
    /// is not affected by system clock changes and continues during sleep.
    private func currentTimestampNs() -> UInt64 {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let ticks = mach_continuous_time()
        return ticks * UInt64(info.numer) / UInt64(info.denom)
    }
}
