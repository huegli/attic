// =============================================================================
// ui.ts — Web client UI controls and status display
// =============================================================================
//
// Manages the floating status indicators (connection, joystick overlay) and
// the focus overlay that prompts users to click the canvas for keyboard input.
// =============================================================================

import { AudioPlayer } from './audio-player';
import type { JoystickState } from './gamepad-handler';

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
// Joystick overlay colors (matching AtticGUI JoystickOverlayView.swift)
// ---------------------------------------------------------------------------

/** Bright green for active directions. */
const JOY_ACTIVE = '#2ecc71';

/** Dim gray for inactive directions. */
const JOY_INACTIVE = 'rgba(255,255,255,0.2)';

/** Red for fire button when pressed. */
const FIRE_ACTIVE = '#e74c3c';

// ---------------------------------------------------------------------------
// UI Manager
// ---------------------------------------------------------------------------

/**
 * Manages the web client's UI elements: floating status indicators, joystick
 * overlay, and the focus overlay.
 *
 * All DOM element lookups happen in the constructor. Event listeners are
 * wired up in `init()`.
 */
export class UI {
  private statusEl: HTMLElement;
  private statusDot: HTMLElement;
  private overlay: HTMLElement;
  private canvas: HTMLCanvasElement;

  // Joystick overlay elements
  private joystickOverlay: HTMLElement;
  private joyUp: SVGElement;
  private joyDown: SVGElement;
  private joyLeft: SVGElement;
  private joyRight: SVGElement;
  private joyFire: SVGElement;

  private audioPlayer: AudioPlayer;

  constructor(audioPlayer: AudioPlayer) {
    this.audioPlayer = audioPlayer;

    // Look up DOM elements (must exist in index.html)
    this.statusEl = document.getElementById('status-text')!;
    this.statusDot = document.getElementById('status-dot')!;
    this.overlay = document.getElementById('overlay')!;
    this.canvas = document.getElementById('screen') as HTMLCanvasElement;

    // Joystick overlay SVG elements
    this.joystickOverlay = document.getElementById('joystick-overlay')!;
    this.joyUp = document.getElementById('joy-up') as unknown as SVGElement;
    this.joyDown = document.getElementById('joy-down') as unknown as SVGElement;
    this.joyLeft = document.getElementById('joy-left') as unknown as SVGElement;
    this.joyRight = document.getElementById('joy-right') as unknown as SVGElement;
    this.joyFire = document.getElementById('joy-fire') as unknown as SVGElement;
  }

  /** Wire up event listeners and focus handling. */
  init(): void {
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
      // Small delay to avoid flicker when clicking elsewhere
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
  }

  /** Update the connection status indicator. */
  setConnectionState(state: ConnectionState): void {
    this.statusDot.style.backgroundColor = STATUS_COLORS[state];
    this.statusEl.textContent = STATUS_TEXT[state];
  }

  /**
   * Show or hide the joystick overlay based on gamepad connection count.
   *
   * Mirrors AtticGUI's JoystickOverlayView visibility logic: only visible
   * when a controller is connected.
   */
  setGamepadCount(count: number): void {
    this.joystickOverlay.style.display = count > 0 ? 'flex' : 'none';
  }

  /**
   * Update the joystick overlay to reflect current port 0 input state.
   *
   * Mirrors AtticGUI's JoystickOverlayView: active directions are bright
   * green, inactive are dim gray. Fire button turns red when pressed.
   */
  setJoystickState(state: JoystickState): void {
    this.joyUp.setAttribute('fill', state.up ? JOY_ACTIVE : JOY_INACTIVE);
    this.joyDown.setAttribute('fill', state.down ? JOY_ACTIVE : JOY_INACTIVE);
    this.joyLeft.setAttribute('fill', state.left ? JOY_ACTIVE : JOY_INACTIVE);
    this.joyRight.setAttribute('fill', state.right ? JOY_ACTIVE : JOY_INACTIVE);
    this.joyFire.setAttribute('fill', state.trigger ? FIRE_ACTIVE : JOY_INACTIVE);
  }
}
