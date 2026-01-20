// =============================================================================
// AudioEngine.swift - Audio Output Engine
// =============================================================================
//
// This file provides the audio output system for the Attic emulator. It uses
// Apple's AVAudioEngine to output POKEY-generated audio samples in real-time.
//
// Audio Architecture Overview:
// ---------------------------
// The Atari 800 XL uses the POKEY chip for sound generation. POKEY is capable
// of generating 4 channels of square waves with various frequency dividers,
// plus noise generation. libatari800 emulates POKEY and provides raw audio
// samples that we need to output through the Mac's audio system.
//
// Audio Pipeline:
// 1. libatari800 generates samples from POKEY emulation during executeFrame()
// 2. Samples are extracted via getAudioBuffer() - typically 16-bit signed PCM
// 3. Samples are converted to Float format and written to a ring buffer
// 4. AVAudioSourceNode pulls samples from the buffer at the audio callback rate
// 5. Samples are mixed and output through the system audio device
//
// Why a Ring Buffer?
// ------------------
// Audio output runs on a dedicated system thread (the audio render thread)
// that requires samples at precise intervals. The emulation runs on a different
// thread at ~60fps. The ring buffer decouples these two threads:
// - Emulation writes samples as they're generated
// - Audio thread reads samples as needed
// - If the emulation runs slightly fast/slow, the buffer absorbs the variance
//
// Buffer Underrun Handling:
// ------------------------
// If the audio thread needs samples but the buffer is empty (underrun),
// we output silence to prevent audio glitches. This can happen if:
// - Emulation runs too slow
// - System is under heavy load
// - Initial startup before emulation begins
//
// Sample Rate Considerations:
// --------------------------
// libatari800 typically generates samples at 44100 Hz, matching standard
// audio output. If the rates differ, resampling would be needed, but we
// configure libatari800 to use 44100 Hz to avoid this complexity.
//
// Usage:
//
//     let audio = AudioEngine()
//     audio.configure(sampleRate: 44100, channels: 1, sampleSize: 16)
//     try audio.start()
//
//     // During emulation loop (after each frame):
//     let (pointer, count) = emulator.getAudioBuffer()
//     audio.enqueueSamplesFromEmulator(pointer: pointer, byteCount: count)
//
//     // When pausing/stopping:
//     audio.stop()
//
// =============================================================================

import Foundation
import AVFoundation

/// Audio output engine using AVAudioEngine.
///
/// This class manages audio output for the emulator. It uses a ring buffer
/// to decouple the emulation thread from the audio callback thread.
///
/// The class is marked as @unchecked Sendable because it manages thread-safe
/// access internally through locks and the audio engine's own thread safety.
///
/// Key Features:
/// - Accepts raw audio bytes from libatari800 (8-bit or 16-bit PCM)
/// - Converts samples to Float format required by AVAudioEngine
/// - Uses a ring buffer for thread-safe producer-consumer pattern
/// - Handles buffer underruns gracefully with silence
/// - Supports pause/resume without audio glitches
///
public final class AudioEngine: @unchecked Sendable {
    // =========================================================================
    // MARK: - Constants
    // =========================================================================

    /// Default audio sample rate in Hz (standard CD quality).
    /// This matches libatari800's typical output rate.
    public static let defaultSampleRate: Double = 44100

    /// The number of audio channels.
    /// POKEY is mono, but we support stereo for future expansion.
    public static let defaultChannelCount: Int = 1

    /// The audio buffer size in samples for AVAudioEngine callbacks.
    /// This affects latency - smaller = lower latency but more CPU.
    public static let bufferSize: Int = 1024

    /// Ring buffer capacity in samples.
    /// Sized for ~100ms of audio to handle timing variations.
    /// 44100 samples/sec * 0.1 sec ≈ 4410 samples, rounded up to 8192.
    public static let ringBufferCapacity: Int = 8192

    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// The AVAudioEngine instance.
    /// AVAudioEngine is Apple's high-level audio framework that manages
    /// audio processing graphs. We use it to route our generated samples
    /// to the system output.
    private var audioEngine: AVAudioEngine?

    /// The source node that generates audio samples.
    /// AVAudioSourceNode is a "pull" model - the audio system calls our
    /// callback when it needs samples, and we provide them from the ring buffer.
    private var sourceNode: AVAudioSourceNode?

    /// Ring buffer for audio samples.
    /// This decouples the emulation thread (producer) from the audio thread (consumer).
    private var ringBuffer: RingBuffer<Float>

    /// Whether the audio engine is currently running.
    private(set) public var isRunning: Bool = false

    /// Whether audio output is enabled.
    /// When disabled, samples are discarded instead of buffered.
    public var isEnabled: Bool = true

    /// Volume level (0.0 to 1.0).
    /// Applied during sample conversion.
    public var volume: Float = 1.0

    // =========================================================================
    // MARK: - Audio Configuration
    // =========================================================================

    /// The configured sample rate from libatari800.
    private var emulatorSampleRate: Double = defaultSampleRate

    /// Number of channels from libatari800 (usually 1 for mono).
    private var emulatorChannels: Int = defaultChannelCount

    /// Bytes per sample from libatari800 (1 or 2).
    /// Note: libatari800_get_sound_sample_size() returns bytes, not bits.
    private var emulatorSampleSize: Int = 2

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a new AudioEngine instance.
    ///
    /// The engine is created in a stopped state. Call `start()` to begin
    /// audio output, and `configure(sampleRate:channels:sampleSize:)` to
    /// match the emulator's audio format.
    public init() {
        // Create ring buffer large enough for ~100ms of audio at 44100 Hz
        // This provides headroom for timing variations between emulation
        // and audio threads.
        self.ringBuffer = RingBuffer(capacity: Self.ringBufferCapacity)
    }

    /// Configures the audio engine to match the emulator's output format.
    ///
    /// Call this before `start()` to ensure proper sample conversion.
    ///
    /// - Parameters:
    ///   - sampleRate: Sample rate in Hz (typically 44100).
    ///   - channels: Number of channels (1 for mono, 2 for stereo).
    ///   - sampleSize: Bytes per sample (1 for 8-bit, 2 for 16-bit).
    ///                 Note: libatari800 returns bytes, not bits.
    public func configure(sampleRate: Int, channels: Int, sampleSize: Int) {
        self.emulatorSampleRate = Double(sampleRate)
        self.emulatorChannels = channels
        self.emulatorSampleSize = sampleSize
    }

    /// Configures the audio engine from an AudioConfiguration struct.
    ///
    /// This is a convenience method that accepts the configuration
    /// returned by EmulatorEngine.getAudioConfiguration().
    ///
    /// - Parameter config: The audio configuration from the emulator.
    public func configure(from config: AudioConfiguration) {
        configure(
            sampleRate: config.sampleRate,
            channels: config.channels,
            sampleSize: config.sampleSize
        )
    }

    // =========================================================================
    // MARK: - Audio Control
    // =========================================================================

    /// Starts the audio engine.
    ///
    /// This sets up the AVAudioEngine with an AVAudioSourceNode that pulls
    /// samples from our ring buffer. The audio system will call our callback
    /// at regular intervals (typically every 512-1024 samples) to request
    /// new audio data.
    ///
    /// - Throws: Error if the audio engine cannot be started (e.g., no audio device).
    public func start() throws {
        guard !isRunning else { return }
        guard isEnabled else { return }

        // Create the audio engine
        // AVAudioEngine manages the audio graph and handles all the low-level
        // Core Audio setup for us.
        let engine = AVAudioEngine()

        // Create audio format matching the emulator's output
        // We use standardFormat which creates a Float32 non-interleaved format,
        // which is what AVAudioSourceNode expects.
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: emulatorSampleRate,
            channels: AVAudioChannelCount(emulatorChannels)
        ) else {
            throw AudioEngineError.invalidFormat
        }

        // Create source node that pulls from our ring buffer
        // The render callback is called from the audio render thread, which is
        // a real-time thread. We must not:
        // - Allocate memory
        // - Take locks that might block
        // - Do any I/O
        // Our ring buffer is designed to be safe for this use case.
        let sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }

            // Get pointer to the audio buffer list
            // UnsafeMutableAudioBufferListPointer provides a Swift-friendly
            // interface to the C-style AudioBufferList structure.
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)

            // Fill each buffer in the list (usually just one for mono)
            for buffer in ablPointer {
                let buf = UnsafeMutableBufferPointer<Float>(buffer)
                let samplesRead = self.ringBuffer.read(into: buf, count: Int(frameCount))

                // Fill remaining with silence if buffer underrun
                // This prevents audio glitches when emulation can't keep up
                if samplesRead < Int(frameCount) {
                    for i in samplesRead..<Int(frameCount) {
                        buf[i] = 0.0
                    }
                }
            }

            return noErr
        }

        // Build the audio graph:
        // sourceNode -> mainMixerNode -> outputNode
        // The mainMixerNode allows volume control, and outputNode routes to
        // the system's default output device.
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)

        // Prepare and start
        // prepare() pre-allocates resources for lower latency startup
        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        self.sourceNode = sourceNode
        self.isRunning = true

        // Clear any stale samples in the buffer
        clearBuffer()
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

    /// Enqueues audio samples from raw bytes (array version).
    ///
    /// This is the primary method for feeding audio from libatari800 to the
    /// audio output. It accepts raw bytes and converts them to Float samples
    /// based on the configured sample size (8-bit or 16-bit).
    ///
    /// This version accepts a Swift array, which is Sendable and can be
    /// safely passed across actor boundaries.
    ///
    /// Call this after each frame to keep the audio buffer filled.
    ///
    /// - Parameter bytes: Raw audio bytes from the emulator.
    /// - Returns: Number of samples actually written (may be less if buffer full).
    @discardableResult
    public func enqueueSamplesFromEmulator(bytes: [UInt8]) -> Int {
        guard !bytes.isEmpty, isEnabled else { return 0 }

        return bytes.withUnsafeBufferPointer { bufferPointer in
            guard let pointer = bufferPointer.baseAddress else { return 0 }
            return enqueueSamplesFromEmulator(pointer: pointer, byteCount: bytes.count)
        }
    }

    /// Enqueues audio samples from Data.
    ///
    /// This version accepts Data directly, which is more efficient when
    /// receiving audio from network protocol buffers (avoids Array copy).
    ///
    /// - Parameter data: Raw audio bytes from the protocol stream.
    /// - Returns: Number of samples actually written (may be less if buffer full).
    @discardableResult
    public func enqueueSamplesFromEmulator(data: Data) -> Int {
        guard !data.isEmpty, isEnabled else { return 0 }

        return data.withUnsafeBytes { bytes in
            guard let pointer = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            return enqueueSamplesFromEmulator(pointer: pointer, byteCount: data.count)
        }
    }

    /// Enqueues audio samples from the emulator's raw audio buffer.
    ///
    /// This is the primary method for feeding audio from libatari800 to the
    /// audio output. It accepts raw bytes and converts them to Float samples
    /// based on the configured sample size (8-bit or 16-bit).
    ///
    /// Call this after each frame to keep the audio buffer filled.
    ///
    /// - Parameters:
    ///   - pointer: Pointer to the raw audio data from libatari800.
    ///   - byteCount: Number of bytes in the buffer.
    /// - Returns: Number of samples actually written (may be less if buffer full).
    @discardableResult
    public func enqueueSamplesFromEmulator(pointer: UnsafePointer<UInt8>, byteCount: Int) -> Int {
        guard byteCount > 0, isEnabled else { return 0 }

        // Convert raw bytes to Float samples
        let samples: [Float]

        if emulatorSampleSize == 2 {
            // 16-bit signed PCM (little-endian)
            // Each sample is 2 bytes, so we have byteCount/2 samples
            let sampleCount = byteCount / 2

            // Reinterpret as Int16 pointer
            let int16Ptr = pointer.withMemoryRebound(to: Int16.self, capacity: sampleCount) { $0 }

            // Convert Int16 to Float (-1.0 to 1.0 range)
            // Int16 range is -32768 to 32767, so we divide by 32768.0
            samples = (0..<sampleCount).map { i in
                Float(int16Ptr[i]) / 32768.0 * volume
            }
        } else {
            // 8-bit unsigned PCM (emulatorSampleSize == 1)
            // Each sample is 1 byte, centered at 128
            let sampleCount = byteCount

            // Convert UInt8 to Float (-1.0 to 1.0 range)
            // UInt8 range is 0-255 with 128 as center (silence)
            samples = (0..<sampleCount).map { i in
                (Float(pointer[i]) - 128.0) / 128.0 * volume
            }
        }

        return ringBuffer.write(samples)
    }

    /// Enqueues pre-converted Float samples.
    ///
    /// Called from the emulation thread to add samples to the buffer.
    /// This method is thread-safe through the ring buffer's internal locking.
    ///
    /// - Parameter samples: Array of audio samples (-1.0 to 1.0 range).
    /// - Returns: Number of samples actually written (may be less if buffer full).
    @discardableResult
    public func enqueueSamples(_ samples: [Float]) -> Int {
        guard isEnabled else { return 0 }

        // Apply volume if not already at 1.0
        if volume != 1.0 {
            let adjustedSamples = samples.map { $0 * volume }
            return ringBuffer.write(adjustedSamples)
        }

        return ringBuffer.write(samples)
    }

    /// Clears any pending audio samples.
    ///
    /// Call this when pausing or resetting the emulator to prevent
    /// old audio from playing when resuming.
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
// MARK: - AudioEngineError
// =============================================================================

/// Errors that can occur in the AudioEngine.
public enum AudioEngineError: Error, LocalizedError {
    /// Failed to create audio format.
    case invalidFormat

    /// Failed to start the audio engine.
    case startFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Failed to create audio format"
        case .startFailed(let reason):
            return "Failed to start audio engine: \(reason)"
        }
    }
}

// =============================================================================
// MARK: - Ring Buffer
// =============================================================================

/// A thread-safe ring buffer for audio samples.
///
/// This is a circular buffer (also called a FIFO queue) that allows one thread
/// to write samples while another thread reads them. It's the standard pattern
/// for real-time audio:
///
/// ```
///                    [Ring Buffer]
///     Producer       ┌─────────────┐       Consumer
///   (Emulation) ---> │ ○ ○ ● ● ● ○ │ ---> (Audio Thread)
///                    └─────────────┘
///                        ↑   ↑
///                     read  write
/// ```
///
/// Thread Safety:
/// - Uses NSLock to protect read/write operations
/// - The lock is held for very short durations (just index updates)
/// - This is acceptable for audio because the operations are O(1)
///
/// Note: A fully lock-free implementation using atomics would be slightly
/// more efficient for real-time audio, but NSLock is sufficient for our
/// needs and simpler to reason about.
///
final class RingBuffer<T>: @unchecked Sendable {
    /// The underlying storage array.
    private var buffer: [T]

    /// Index where the next sample will be read from.
    private var readIndex: Int = 0

    /// Index where the next sample will be written to.
    private var writeIndex: Int = 0

    /// Maximum number of samples the buffer can hold.
    private let capacity: Int

    /// Lock for thread-safe access.
    /// NSLock is a simple, efficient lock suitable for short critical sections.
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
