// =============================================================================
// main.ts — Attic Web Client entry point
// =============================================================================
//
// Wires together all modules: AESP protocol client, video renderer, audio
// player, keyboard handler, and UI controls. This is the only file that
// knows about all modules — each module is independent and testable.
// =============================================================================

import { AESPClient } from './aesp-client';
import { VideoRenderer } from './video-renderer';
import { AudioPlayer } from './audio-player';
import { KeyboardHandler } from './keyboard-handler';
import { GamepadHandler } from './gamepad-handler';
import { UI } from './ui';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

// WebSocket bridge URL — defaults to localhost:47803 (AtticServer --websocket).
// Can be overridden via URL search params: ?ws=ws://hostname:port
const params = new URLSearchParams(window.location.search);
const wsUrl = params.get('ws') ?? 'ws://localhost:47803';

// ---------------------------------------------------------------------------
// Module initialization
// ---------------------------------------------------------------------------

const canvas = document.getElementById('screen') as HTMLCanvasElement;

// Audio player — initialized lazily on first user interaction (browser policy)
const audioPlayer = new AudioPlayer();

// Video renderer — starts the requestAnimationFrame loop
const renderer = new VideoRenderer(canvas);
renderer.start();

// AESP protocol client — connects to the WebSocket bridge
const client = new AESPClient(wsUrl, {
  onFrame: (pixels) => renderer.drawFrame(pixels),
  onFrameDelta: (payload) => renderer.applyDelta(payload),
  onAudio: (samples) => audioPlayer.enqueueSamples(samples),
  onConnect: () => ui.setConnectionState('connected'),
  onDisconnect: () => ui.setConnectionState('disconnected'),
  onError: (code, msg) => console.error(`[AESP] Error ${code}: ${msg}`),
});

// Keyboard handler — maps browser keys to Atari input
const keyboard = new KeyboardHandler(client, canvas);
keyboard.attach();

// UI — status indicators, joystick overlay, focus overlay
const ui = new UI(audioPlayer);
ui.init();

// Gamepad handler — maps browser Gamepad API to Atari joystick input.
// Supports standard controllers (Xbox, PS) and generic HID joysticks (CX Stick).
const gamepad = new GamepadHandler(
  client,
  (count) => ui.setGamepadCount(count),
  (state) => ui.setJoystickState(state),
);
gamepad.attach();

// ---------------------------------------------------------------------------
// Connect
// ---------------------------------------------------------------------------

ui.setConnectionState('connecting');
client.connect();
