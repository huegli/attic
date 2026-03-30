// =============================================================================
// video-renderer.ts — Canvas 2D renderer for Atari video frames
// =============================================================================
//
// Renders AESP FRAME_RAW and FRAME_DELTA messages onto an HTML5 canvas.
// The Atari outputs 336x240 BGRA pixels, but Canvas 2D uses RGBA, so
// we swap B and R channels during rendering.
//
// Delta frames contain only changed pixels as (index, BGRA) tuples,
// which are applied to the persistent ImageData buffer.
//
// Rendering is driven by requestAnimationFrame with a dirty flag to avoid
// redundant putImageData calls when no new frame has arrived.
// =============================================================================

import { FRAME_WIDTH, FRAME_HEIGHT } from './aesp-client';

/**
 * Renders Atari video frames onto a <canvas> element.
 *
 * Maintains a persistent ImageData buffer that accumulates delta updates.
 * Only calls putImageData on requestAnimationFrame when the buffer is dirty.
 */
export class VideoRenderer {
  private canvas: HTMLCanvasElement;
  private ctx: CanvasRenderingContext2D;
  private imageData: ImageData;
  private dirty = false;
  private animFrameId = 0;

  constructor(canvas: HTMLCanvasElement) {
    this.canvas = canvas;
    this.canvas.width = FRAME_WIDTH;
    this.canvas.height = FRAME_HEIGHT;

    const ctx = canvas.getContext('2d', { alpha: false });
    if (!ctx) throw new Error('Failed to get 2D context');
    this.ctx = ctx;

    // Persistent ImageData buffer — accumulates deltas between full frames
    this.imageData = ctx.createImageData(FRAME_WIDTH, FRAME_HEIGHT);

    // Fill with black initially (RGBA: 0,0,0,255)
    const data = this.imageData.data;
    for (let i = 3; i < data.length; i += 4) {
      data[i] = 255; // Alpha
    }
  }

  /** Start the render loop (requestAnimationFrame). */
  start(): void {
    const loop = () => {
      if (this.dirty) {
        this.ctx.putImageData(this.imageData, 0, 0);
        this.dirty = false;
      }
      this.animFrameId = requestAnimationFrame(loop);
    };
    this.animFrameId = requestAnimationFrame(loop);
  }

  /** Stop the render loop. */
  stop(): void {
    cancelAnimationFrame(this.animFrameId);
  }

  /**
   * Applies a full FRAME_RAW (BGRA pixels) to the canvas buffer.
   *
   * Converts BGRA to RGBA using 32-bit integer operations for speed.
   * At 60fps this processes 322,560 bytes per frame — the Uint32Array
   * approach is ~4x faster than byte-by-byte swapping.
   *
   * @param bgra The raw BGRA pixel data (336 * 240 * 4 bytes).
   */
  drawFrame(bgra: Uint8Array): void {
    const dst = this.imageData.data;

    // Use 32-bit views for fast BGRA→RGBA channel swap.
    // BGRA in memory (LE): B at byte 0, G at byte 1, R at byte 2, A at byte 3
    // As a 32-bit LE integer: 0xAARRGGBB
    // We need RGBA: R at byte 0, G at byte 1, B at byte 2, A at byte 3
    // As a 32-bit LE integer: 0xAABBGGRR
    // Swap: keep G and A in place, swap B and R.
    const src32 = new Uint32Array(bgra.buffer, bgra.byteOffset, bgra.byteLength >> 2);
    const dst32 = new Uint32Array(dst.buffer);

    for (let i = 0; i < src32.length; i++) {
      const bgra32 = src32[i];
      // Swap B (bits 0-7) and R (bits 16-23), keep G (8-15) and A (24-31)
      dst32[i] = (bgra32 & 0xFF00FF00)        // G + A unchanged
              | ((bgra32 & 0x000000FF) << 16)  // B → R position
              | ((bgra32 >> 16) & 0x000000FF); // R → B position
    }

    this.dirty = true;
  }

  /**
   * Applies a FRAME_DELTA to the canvas buffer.
   *
   * Delta payload format: N repetitions of 8-byte entries:
   *   - 4 bytes: pixel index (big-endian UInt32)
   *   - 4 bytes: B, G, R, A color values
   *
   * Each entry updates one pixel in the persistent ImageData buffer.
   * An empty payload (0 bytes) means the frame is identical to the previous.
   *
   * @param payload The delta-encoded pixel data.
   */
  applyDelta(payload: Uint8Array): void {
    if (payload.byteLength === 0) {
      // No changes — still mark dirty if this is the first frame
      return;
    }

    const view = new DataView(payload.buffer, payload.byteOffset, payload.byteLength);
    const dst = this.imageData.data;

    for (let off = 0; off < payload.byteLength; off += 8) {
      const pixelIndex = view.getUint32(off); // big-endian pixel index
      const byteOff = pixelIndex * 4;

      // Delta bytes are B, G, R, A — write as R, G, B, A into RGBA buffer
      dst[byteOff]     = payload[off + 6]; // R (from BGRA offset 2)
      dst[byteOff + 1] = payload[off + 5]; // G (from BGRA offset 1)
      dst[byteOff + 2] = payload[off + 4]; // B (from BGRA offset 0)
      dst[byteOff + 3] = payload[off + 7]; // A (from BGRA offset 3)
    }

    this.dirty = true;
  }
}
