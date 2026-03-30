// =============================================================================
// audio-player.ts — Web Audio API playback for Atari audio
// =============================================================================
//
// Plays 44.1kHz 16-bit signed PCM mono audio received from the emulator.
// Uses AudioWorklet for low-latency playback with a ring buffer to absorb
// network jitter.
//
// The worklet processor is loaded as a Blob URL to keep the deployment
// self-contained (single HTML file, no separate JS files needed).
//
// Audio flow:
//   AESP AUDIO_PCM → Int16 LE → Float32 → port.postMessage → Worklet → speaker
// =============================================================================

// ---------------------------------------------------------------------------
// AudioWorklet processor source (runs in a separate thread)
// ---------------------------------------------------------------------------

/**
 * Source code for the AudioWorkletProcessor that runs in the audio thread.
 * It maintains a ring buffer of Float32 samples and fills output blocks
 * from it. If the buffer underruns, it outputs silence.
 */
const WORKLET_SOURCE = `
class AtariAudioProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    // Ring buffer: 8192 samples (~186ms at 44.1kHz)
    this.buffer = new Float32Array(8192);
    this.writePos = 0;
    this.readPos = 0;
    this.count = 0; // Number of samples available

    this.port.onmessage = (e) => {
      const samples = e.data;
      for (let i = 0; i < samples.length; i++) {
        if (this.count < this.buffer.length) {
          this.buffer[this.writePos] = samples[i];
          this.writePos = (this.writePos + 1) % this.buffer.length;
          this.count++;
        }
        // If buffer is full, drop oldest samples
      }
    };
  }

  process(inputs, outputs) {
    const output = outputs[0][0]; // Mono channel
    if (!output) return true;

    for (let i = 0; i < output.length; i++) {
      if (this.count > 0) {
        output[i] = this.buffer[this.readPos];
        this.readPos = (this.readPos + 1) % this.buffer.length;
        this.count--;
      } else {
        output[i] = 0; // Silence on underrun
      }
    }

    return true; // Keep processor alive
  }
}

registerProcessor('atari-audio-processor', AtariAudioProcessor);
`;

// ---------------------------------------------------------------------------
// AudioPlayer
// ---------------------------------------------------------------------------

/**
 * Plays Atari audio samples using the Web Audio API.
 *
 * Samples arrive as 16-bit signed PCM (little-endian, mono, 44.1kHz)
 * from AESP AUDIO_PCM messages. They're converted to Float32 and
 * forwarded to an AudioWorkletProcessor via MessagePort.
 *
 * Usage:
 * ```ts
 * const player = new AudioPlayer();
 * await player.init();
 * // In AESP callback:
 * player.enqueueSamples(pcmPayload);
 * ```
 */
export class AudioPlayer {
  private ctx: AudioContext | null = null;
  private workletNode: AudioWorkletNode | null = null;
  private _muted = false;

  /**
   * Initializes the AudioContext and AudioWorklet.
   *
   * Must be called from a user gesture (click/keypress) due to browser
   * autoplay policies that require user interaction before audio playback.
   */
  async init(): Promise<void> {
    if (this.ctx) return; // Already initialized

    // Create AudioContext at the Atari's sample rate
    this.ctx = new AudioContext({ sampleRate: 44100 });

    // Load the worklet processor from a Blob URL.
    // This avoids requiring a separate .js file to be served alongside
    // the main page, keeping deployment simple.
    const blob = new Blob([WORKLET_SOURCE], { type: 'application/javascript' });
    const url = URL.createObjectURL(blob);
    await this.ctx.audioWorklet.addModule(url);
    URL.revokeObjectURL(url);

    // Create the worklet node and connect it to the audio output
    this.workletNode = new AudioWorkletNode(this.ctx, 'atari-audio-processor');
    this.workletNode.connect(this.ctx.destination);
  }

  /**
   * Enqueues raw PCM audio samples for playback.
   *
   * Converts 16-bit signed PCM (little-endian) to Float32 and sends
   * the samples to the AudioWorklet processor via its MessagePort.
   *
   * @param pcmData Raw bytes from an AESP AUDIO_PCM message payload.
   *                Each sample is 2 bytes (Int16 LE).
   */
  enqueueSamples(pcmData: Uint8Array): void {
    if (!this.workletNode || this._muted) return;

    // Convert Int16 LE to Float32
    const sampleCount = pcmData.byteLength >> 1; // 2 bytes per sample
    const float32 = new Float32Array(sampleCount);
    const view = new DataView(pcmData.buffer, pcmData.byteOffset, pcmData.byteLength);

    for (let i = 0; i < sampleCount; i++) {
      // Read as little-endian Int16 (macOS/Apple Silicon is LE)
      const int16 = view.getInt16(i * 2, true);
      float32[i] = int16 / 32768.0;
    }

    // Transfer to audio worklet thread
    this.workletNode.port.postMessage(float32);
  }

  /** Whether audio is currently muted. */
  get muted(): boolean {
    return this._muted;
  }

  /** Toggle mute state. Suspends/resumes the AudioContext. */
  async toggleMute(): Promise<void> {
    if (!this.ctx) return;

    if (this._muted) {
      await this.ctx.resume();
      this._muted = false;
    } else {
      await this.ctx.suspend();
      this._muted = true;
    }
  }
}
