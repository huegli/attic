// =============================================================================
// aesp-client.ts — WebSocket client for the AESP binary protocol
// =============================================================================
//
// Connects to the AtticServer WebSocket bridge and handles AESP binary message
// encoding/decoding. All AESP messages share an 8-byte header:
//
//   Offset  Size  Field    Format
//   0       2     Magic    0xAE50 (big-endian)
//   2       1     Version  0x01
//   3       1     Type     Message type (0x00-0x9F)
//   4       4     Length   Payload size (big-endian)
//   8       N     Payload  Type-specific data
//
// This client provides typed callbacks for each message category (video, audio,
// control) and handles auto-reconnect with exponential backoff.
// =============================================================================

// ---------------------------------------------------------------------------
// Protocol constants (mirrors AESPConstants in Swift)
// ---------------------------------------------------------------------------

const AESP_MAGIC = 0xAE50;
const AESP_VERSION = 0x01;
const HEADER_SIZE = 8;

/** AESP message type byte values. */
export const MsgType = {
  // Control (0x00-0x3F)
  PING:              0x00,
  PONG:              0x01,
  PAUSE:             0x02,
  RESUME:            0x03,
  RESET:             0x04,
  STATUS:            0x05,
  INFO:              0x06,
  BOOT_FILE:         0x07,
  ACK:               0x0F,
  ERROR:             0x3F,
  // Input (0x40-0x5F)
  KEY_DOWN:          0x40,
  KEY_UP:            0x41,
  JOYSTICK:          0x42,
  CONSOLE_KEYS:      0x43,
  PADDLE:            0x44,
  // Video (0x60-0x7F)
  FRAME_RAW:         0x60,
  FRAME_DELTA:       0x61,
  FRAME_CONFIG:      0x62,
  VIDEO_SUBSCRIBE:   0x63,
  VIDEO_UNSUBSCRIBE: 0x64,
  // Audio (0x80-0x9F)
  AUDIO_PCM:         0x80,
  AUDIO_CONFIG:      0x81,
  AUDIO_SYNC:        0x82,
  AUDIO_SUBSCRIBE:   0x83,
  AUDIO_UNSUBSCRIBE: 0x84,
} as const;

/** Video frame dimensions. */
export const FRAME_WIDTH = 336;
export const FRAME_HEIGHT = 240;
export const FRAME_BYTES_PER_PIXEL = 4; // BGRA
export const FRAME_SIZE = FRAME_WIDTH * FRAME_HEIGHT * FRAME_BYTES_PER_PIXEL;

// ---------------------------------------------------------------------------
// Callbacks
// ---------------------------------------------------------------------------

export interface AESPCallbacks {
  /** Full BGRA frame (322,560 bytes). */
  onFrame?: (pixels: Uint8Array) => void;
  /** Delta-encoded frame: array of (pixelIndex, B, G, R, A) entries. */
  onFrameDelta?: (payload: Uint8Array) => void;
  /** Raw 16-bit signed PCM audio samples (little-endian). */
  onAudio?: (samples: Uint8Array) => void;
  /** Audio sync with frame number for A/V correlation. */
  onAudioSync?: (frameNumber: number) => void;
  /** Connection established. */
  onConnect?: () => void;
  /** Connection lost. */
  onDisconnect?: () => void;
  /** Error message from server. */
  onError?: (code: number, message: string) => void;
  /** Status response. */
  onStatus?: (isRunning: boolean) => void;
}

// ---------------------------------------------------------------------------
// AESPClient
// ---------------------------------------------------------------------------

/**
 * WebSocket client for the Attic Emulator Server Protocol.
 *
 * Connects to the WebSocket bridge on port 47803 (default) and decodes
 * incoming AESP binary messages into typed callbacks. Provides methods
 * to send control and input messages back to the server.
 *
 * Usage:
 * ```ts
 * const client = new AESPClient('ws://localhost:47803', {
 *   onFrame: (pixels) => renderer.drawFrame(pixels),
 *   onAudio: (samples) => audioPlayer.enqueueSamples(samples),
 *   onConnect: () => statusEl.textContent = 'Connected',
 * });
 * client.connect();
 * ```
 */
export class AESPClient {
  private ws: WebSocket | null = null;
  private url: string;
  private callbacks: AESPCallbacks;
  private reconnectDelay = 1000;
  private maxReconnectDelay = 10000;
  private shouldReconnect = true;

  constructor(url: string, callbacks: AESPCallbacks) {
    this.url = url;
    this.callbacks = callbacks;
  }

  // -------------------------------------------------------------------------
  // Connection lifecycle
  // -------------------------------------------------------------------------

  /** Opens the WebSocket connection to the bridge. */
  connect(): void {
    this.shouldReconnect = true;
    this.openWebSocket();
  }

  /** Closes the connection and stops auto-reconnect. */
  disconnect(): void {
    this.shouldReconnect = false;
    this.ws?.close();
    this.ws = null;
  }

  /** Whether the WebSocket is currently open. */
  get connected(): boolean {
    return this.ws?.readyState === WebSocket.OPEN;
  }

  private openWebSocket(): void {
    const ws = new WebSocket(this.url);
    ws.binaryType = 'arraybuffer';

    ws.onopen = () => {
      this.reconnectDelay = 1000; // Reset backoff on successful connect
      this.callbacks.onConnect?.();
      // Auto-subscribe to video (with delta encoding) and audio
      this.send(MsgType.VIDEO_SUBSCRIBE, new Uint8Array([0x01]));
      this.send(MsgType.AUDIO_SUBSCRIBE);
    };

    ws.onmessage = (event: MessageEvent) => {
      if (event.data instanceof ArrayBuffer) {
        this.handleMessage(event.data);
      }
    };

    ws.onclose = () => {
      this.ws = null;
      this.callbacks.onDisconnect?.();
      if (this.shouldReconnect) {
        setTimeout(() => this.openWebSocket(), this.reconnectDelay);
        this.reconnectDelay = Math.min(
          this.reconnectDelay * 2,
          this.maxReconnectDelay,
        );
      }
    };

    ws.onerror = () => {
      // onerror is always followed by onclose, so reconnect logic is there
    };

    this.ws = ws;
  }

  // -------------------------------------------------------------------------
  // Message decoding
  // -------------------------------------------------------------------------

  private handleMessage(buffer: ArrayBuffer): void {
    if (buffer.byteLength < HEADER_SIZE) return;

    const view = new DataView(buffer);
    const magic = view.getUint16(0); // big-endian
    if (magic !== AESP_MAGIC) return;

    const type = view.getUint8(3);
    const length = view.getUint32(4); // big-endian

    if (buffer.byteLength < HEADER_SIZE + length) return;

    const payload = new Uint8Array(buffer, HEADER_SIZE, length);

    switch (type) {
      case MsgType.FRAME_RAW:
        this.callbacks.onFrame?.(payload);
        break;

      case MsgType.FRAME_DELTA:
        this.callbacks.onFrameDelta?.(payload);
        break;

      case MsgType.AUDIO_PCM:
        this.callbacks.onAudio?.(payload);
        break;

      case MsgType.AUDIO_SYNC:
        if (payload.byteLength >= 8) {
          // 8-byte big-endian frame number (use lower 32 bits for JS safety)
          const frameNum = view.getUint32(HEADER_SIZE + 4);
          this.callbacks.onAudioSync?.(frameNum);
        }
        break;

      case MsgType.STATUS:
        if (payload.byteLength >= 1) {
          this.callbacks.onStatus?.(payload[0] !== 0);
        }
        break;

      case MsgType.ERROR:
        if (payload.byteLength >= 1) {
          const code = payload[0];
          const msg = new TextDecoder().decode(payload.subarray(1));
          this.callbacks.onError?.(code, msg);
        }
        break;

      case MsgType.PONG:
      case MsgType.ACK:
        // Acknowledged — no action needed
        break;
    }
  }

  // -------------------------------------------------------------------------
  // Message encoding & sending
  // -------------------------------------------------------------------------

  /**
   * Sends an AESP message to the server.
   *
   * Builds the 8-byte header (magic, version, type, length) followed by
   * the optional payload, and sends it as a WebSocket binary frame.
   */
  send(type: number, payload?: Uint8Array): void {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return;

    const payloadLen = payload?.byteLength ?? 0;
    const buffer = new ArrayBuffer(HEADER_SIZE + payloadLen);
    const view = new DataView(buffer);

    // Header
    view.setUint16(0, AESP_MAGIC);       // Magic (big-endian)
    view.setUint8(2, AESP_VERSION);       // Version
    view.setUint8(3, type);               // Type
    view.setUint32(4, payloadLen);        // Length (big-endian)

    // Payload
    if (payload) {
      new Uint8Array(buffer, HEADER_SIZE).set(payload);
    }

    this.ws.send(buffer);
  }

  // -------------------------------------------------------------------------
  // Convenience methods for common messages
  // -------------------------------------------------------------------------

  /** Sends a KEY_DOWN event with the given Atari key parameters. */
  sendKeyDown(keyChar: number, keyCode: number, shift: boolean, control: boolean): void {
    let flags = 0;
    if (shift) flags |= 0x01;
    if (control) flags |= 0x02;
    this.send(MsgType.KEY_DOWN, new Uint8Array([keyChar, keyCode, flags]));
  }

  /** Sends a KEY_UP event (releases any held key). */
  sendKeyUp(): void {
    this.send(MsgType.KEY_UP);
  }

  /** Sends console key state (START, SELECT, OPTION). */
  sendConsoleKeys(start: boolean, select: boolean, option: boolean): void {
    let flags = 0;
    if (start) flags |= 0x01;
    if (select) flags |= 0x02;
    if (option) flags |= 0x04;
    this.send(MsgType.CONSOLE_KEYS, new Uint8Array([flags]));
  }

  /** Sends a PAUSE command. */
  sendPause(): void {
    this.send(MsgType.PAUSE);
  }

  /** Sends a RESUME command. */
  sendResume(): void {
    this.send(MsgType.RESUME);
  }

  /** Sends a RESET command (cold or warm). */
  sendReset(cold: boolean): void {
    this.send(MsgType.RESET, new Uint8Array([cold ? 0x01 : 0x00]));
  }

  /** Sends a PING to check server liveness. */
  sendPing(): void {
    this.send(MsgType.PING);
  }
}
