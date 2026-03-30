// =============================================================================
// ui.ts — Web client UI controls and status display
// =============================================================================
//
// Manages the toolbar (connection status, fullscreen, mute, reset buttons)
// and the focus overlay that prompts users to click the canvas for keyboard
// input. All DOM manipulation is centralized here.
// =============================================================================

import { AESPClient } from './aesp-client';
import { AudioPlayer } from './audio-player';

// ---------------------------------------------------------------------------
// Connection status
// ---------------------------------------------------------------------------

type ConnectionState = 'disconnected' | 'connecting' | 'connected';

const STATUS_COLORS: Record<ConnectionState, string> = {
  disconnected: '#e74c3c', // Red
  connecting:   '#f39c12', // Yellow
  connected:    '#2ecc71', // Green
};

const STATUS_TEXT: Record<ConnectionState, string> = {
  disconnected: 'Disconnected',
  connecting:   'Connecting...',
  connected:    'Connected',
};

// ---------------------------------------------------------------------------
// UI Manager
// ---------------------------------------------------------------------------

/**
 * Manages the web client's UI elements: toolbar buttons, connection status,
 * and the focus overlay.
 *
 * All DOM element lookups happen in the constructor. Event listeners are
 * wired up in `init()`.
 */
export class UI {
  private statusEl: HTMLElement;
  private statusDot: HTMLElement;
  private btnFullscreen: HTMLButtonElement;
  private btnMute: HTMLButtonElement;
  private btnReset: HTMLButtonElement;
  private overlay: HTMLElement;
  private canvas: HTMLCanvasElement;

  private client: AESPClient;
  private audioPlayer: AudioPlayer;

  constructor(client: AESPClient, audioPlayer: AudioPlayer) {
    this.client = client;
    this.audioPlayer = audioPlayer;

    // Look up DOM elements (must exist in index.html)
    this.statusEl = document.getElementById('status-text')!;
    this.statusDot = document.getElementById('status-dot')!;
    this.btnFullscreen = document.getElementById('btn-fullscreen') as HTMLButtonElement;
    this.btnMute = document.getElementById('btn-mute') as HTMLButtonElement;
    this.btnReset = document.getElementById('btn-reset') as HTMLButtonElement;
    this.overlay = document.getElementById('overlay')!;
    this.canvas = document.getElementById('screen') as HTMLCanvasElement;
  }

  /** Wire up button event listeners and focus handling. */
  init(): void {
    // Fullscreen toggle
    this.btnFullscreen.addEventListener('click', () => {
      if (document.fullscreenElement) {
        document.exitFullscreen();
      } else {
        this.canvas.requestFullscreen();
      }
    });

    // Mute toggle
    this.btnMute.addEventListener('click', async () => {
      await this.audioPlayer.toggleMute();
      this.btnMute.textContent = this.audioPlayer.muted ? 'Unmute' : 'Mute';
    });

    // Reset button (warm reset)
    this.btnReset.addEventListener('click', () => {
      this.client.sendReset(false);
    });

    // Focus overlay — click to focus canvas and initialize audio.
    // Audio must be started from a user gesture due to browser autoplay policy.
    this.overlay.addEventListener('click', async () => {
      await this.audioPlayer.init();
      this.canvas.focus();
      this.overlay.style.display = 'none';
    });

    // Also allow clicking the canvas directly when overlay is hidden
    this.canvas.addEventListener('click', async () => {
      await this.audioPlayer.init();
      this.canvas.focus();
    });

    // Show overlay when canvas loses focus
    this.canvas.addEventListener('blur', () => {
      // Small delay to avoid flicker when clicking toolbar buttons
      setTimeout(() => {
        if (document.activeElement !== this.canvas) {
          this.overlay.style.display = 'flex';
        }
      }, 100);
    });

    // Hide overlay when canvas gains focus
    this.canvas.addEventListener('focus', () => {
      this.overlay.style.display = 'none';
    });

    // Update fullscreen button text on fullscreen change
    document.addEventListener('fullscreenchange', () => {
      this.btnFullscreen.textContent = document.fullscreenElement ? 'Exit Fullscreen' : 'Fullscreen';
    });
  }

  /** Update the connection status indicator. */
  setConnectionState(state: ConnectionState): void {
    this.statusDot.style.backgroundColor = STATUS_COLORS[state];
    this.statusEl.textContent = STATUS_TEXT[state];
  }
}
