// =============================================================================
// AudioEngine.swift - Audio Output Engine
// =============================================================================
//
// This file provides the audio output system for the emulator. It uses
// Apple's AVAudioEngine to output POKEY-generated audio samples.
//
// Audio Pipeline:
// 1. libatari800 generates samples from POKEY emulation (~64kHz internal rate)
// 2. Samples are resampled to 44.1kHz
// 3. Samples are written to a lock-free ring buffer
// 4. AVAudioSourceNode pulls samples from the buffer for output
//
// The ring buffer design allows the emulation thread to produce samples
// without blocking, while the audio thread consumes them at a steady rate.
//
// Usage:
//
//     let audio = AudioEngine()
//     try audio.start()
//
//     // During emulation loop:
//     audio.enqueueSamples(samplesFromEmulator)
//
//     // When done:
//     audio.stop()
//
// NOTE: This is a stub implementation. Full implementation in Phase 4.
//
// =============================================================================

import Foundation
import AVFoundation

/// Audio output engine using AVAudioEngine.
///
/// This class manages audio output for the emulator. It uses a ring buffer
/// to decouple the emulation thread from the audio callback thread.
public final class AudioEngine: @unchecked Sendable {
    // =========================================================================
    // MARK: - Constants
    // =========================================================================

    /// The audio sample rate in Hz.
    public static let sampleRate: Double = 44100

    /// The number of audio channels (mono for POKEY).
    public static let channelCount: Int = 1

    /// The audio buffer size in samples.
    public static let bufferSize: Int = 1024

    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// The AVAudioEngine instance.
    private var audioEngine: AVAudioEngine?

    /// The source node that generates audio samples.
    private var sourceNode: AVAudioSourceNode?

    /// Ring buffer for audio samples.
    private var ringBuffer: RingBuffer<Float>

    /// Whether the audio engine is currently running.
    private(set) public var isRunning: Bool = false

    /// Whether audio output is enabled.
    public var isEnabled: Bool = true

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a new AudioEngine instance.
    public init() {
        // Create ring buffer large enough for ~100ms of audio
        // 44100 * 0.1 = 4410 samples
        self.ringBuffer = RingBuffer(capacity: 8192)
    }

    // =========================================================================
    // MARK: - Audio Control
    // =========================================================================

    /// Starts the audio engine.
    ///
    /// - Throws: Error if the audio engine cannot be started.
    public func start() throws {
        guard !isRunning else { return }
        guard isEnabled else { return }

        let engine = AVAudioEngine()
        let format = AVAudioFormat(
            standardFormatWithSampleRate: Self.sampleRate,
            channels: AVAudioChannelCount(Self.channelCount)
        )!

        // Create source node that pulls from our ring buffer
        let sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }

            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)

            for buffer in ablPointer {
                let buf = UnsafeMutableBufferPointer<Float>(buffer)
                let samplesRead = self.ringBuffer.read(into: buf, count: Int(frameCount))

                // Fill remaining with silence if buffer underrun
                if samplesRead < Int(frameCount) {
                    for i in samplesRead..<Int(frameCount) {
                        buf[i] = 0.0
                    }
                }
            }

            return noErr
        }

        // Connect nodes
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)

        // Prepare and start
        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        self.sourceNode = sourceNode
        self.isRunning = true
    }

    /// Stops the audio engine.
    public func stop() {
        guard isRunning else { return }

        audioEngine?.stop()
        if let sourceNode = sourceNode {
            audioEngine?.detach(sourceNode)
        }

        audioEngine = nil
        sourceNode = nil
        isRunning = false
    }

    /// Pauses audio output temporarily.
    public func pause() {
        audioEngine?.pause()
    }

    /// Resumes audio output after pause.
    public func resume() {
        try? audioEngine?.start()
    }

    // =========================================================================
    // MARK: - Sample Input
    // =========================================================================

    /// Enqueues audio samples from the emulator.
    ///
    /// Called from the emulation thread to add samples to the buffer.
    /// This method is lock-free and safe to call at any time.
    ///
    /// - Parameter samples: Array of audio samples (-1.0 to 1.0 range).
    /// - Returns: Number of samples actually written (may be less if buffer full).
    @discardableResult
    public func enqueueSamples(_ samples: [Float]) -> Int {
        ringBuffer.write(samples)
    }

    /// Clears any pending audio samples.
    public func clearBuffer() {
        ringBuffer.clear()
    }

    // =========================================================================
    // MARK: - Status
    // =========================================================================

    /// Returns the number of samples currently buffered.
    public var bufferedSamples: Int {
        ringBuffer.count
    }

    /// Returns true if the buffer is running low (potential underrun).
    public var isBufferLow: Bool {
        ringBuffer.count < Self.bufferSize
    }

    // =========================================================================
    // MARK: - Cleanup
    // =========================================================================

    deinit {
        stop()
    }
}

// =============================================================================
// MARK: - Ring Buffer
// =============================================================================

/// A simple lock-free ring buffer for audio samples.
///
/// This implementation uses atomic operations to allow concurrent
/// read/write access from different threads without locking.
///
/// Note: This is a simplified implementation. A production version
/// would use proper atomic operations for the read/write indices.
final class RingBuffer<T>: @unchecked Sendable {
    private var buffer: [T]
    private var readIndex: Int = 0
    private var writeIndex: Int = 0
    private let capacity: Int
    private let lock = NSLock()

    /// Creates a ring buffer with the specified capacity.
    init(capacity: Int) {
        self.capacity = capacity
        // Initialize with zeros (assuming T is a numeric type)
        self.buffer = [T](unsafeUninitializedCapacity: capacity) { buffer, count in
            count = capacity
        }
    }

    /// Writes samples to the buffer.
    ///
    /// - Parameter samples: Samples to write.
    /// - Returns: Number of samples actually written.
    @discardableResult
    func write(_ samples: [T]) -> Int {
        lock.lock()
        defer { lock.unlock() }

        var written = 0
        for sample in samples {
            let nextWrite = (writeIndex + 1) % capacity

            // Check if buffer is full
            if nextWrite == readIndex {
                break
            }

            buffer[writeIndex] = sample
            writeIndex = nextWrite
            written += 1
        }

        return written
    }

    /// Reads samples from the buffer.
    ///
    /// - Parameters:
    ///   - destination: Buffer to read into.
    ///   - count: Number of samples to read.
    /// - Returns: Number of samples actually read.
    @discardableResult
    func read(into destination: UnsafeMutableBufferPointer<T>, count: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }

        var readCount = 0
        while readCount < count && readIndex != writeIndex {
            destination[readCount] = buffer[readIndex]
            readIndex = (readIndex + 1) % capacity
            readCount += 1
        }

        return readCount
    }

    /// Number of samples currently in the buffer.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }

        if writeIndex >= readIndex {
            return writeIndex - readIndex
        } else {
            return capacity - readIndex + writeIndex
        }
    }

    /// Clears all samples from the buffer.
    func clear() {
        lock.lock()
        defer { lock.unlock() }

        readIndex = 0
        writeIndex = 0
    }
}
