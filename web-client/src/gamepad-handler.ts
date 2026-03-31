// =============================================================================
// gamepad-handler.ts — Browser Gamepad API to Atari joystick mapping
// =============================================================================
//
// Maps physical game controllers to Atari joystick input using the browser's
// Gamepad API. Supports two mapping modes:
//
// 1. Standard mapping (Xbox, PS, MFi controllers) — mirrors the native
//    GameControllerHandler.swift with D-pad, left stick, multiple fire
//    buttons, and console key mapping.
//
// 2. Non-standard mapping (generic HID joysticks like CX Stick) — mirrors
//    the native HIDJoystickManager.swift with raw axes for directions and
//    buttons[0] for fire.
//
// The Gamepad API requires polling (no change events), so we use a
// requestAnimationFrame loop and only send messages when state changes.
//
// Up to 2 controllers are supported, mapped to Atari ports 0 and 1.
// =============================================================================

import { AESPClient } from './aesp-client';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/** Analog stick deadzone — matches Swift GameControllerHandler (0.25). */
const DEADZONE = 0.25;

/** Maximum number of Atari joystick ports (0 and 1). */
const MAX_PORTS = 2;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** Tracks the joystick state for one port to detect changes. */
export interface JoystickState {
  up: boolean;
  down: boolean;
  left: boolean;
  right: boolean;
  trigger: boolean;
}

/** Tracks console key state to detect changes. */
interface ConsoleKeyState {
  start: boolean;
  select: boolean;
  option: boolean;
}

/** Returns a neutral (all-false) joystick state. */
function neutralJoystick(): JoystickState {
  return { up: false, down: false, left: false, right: false, trigger: false };
}

/** Returns a neutral console key state. */
function neutralConsole(): ConsoleKeyState {
  return { start: false, select: false, option: false };
}

/** Compares two joystick states for equality. */
function joystickEqual(a: JoystickState, b: JoystickState): boolean {
  return a.up === b.up && a.down === b.down && a.left === b.left
      && a.right === b.right && a.trigger === b.trigger;
}

/** Compares two console key states for equality. */
function consoleEqual(a: ConsoleKeyState, b: ConsoleKeyState): boolean {
  return a.start === b.start && a.select === b.select && a.option === b.option;
}

// ---------------------------------------------------------------------------
// GamepadHandler
// ---------------------------------------------------------------------------

/**
 * Manages browser gamepad input for the Atari emulator.
 *
 * Polls connected gamepads each animation frame, maps their input to Atari
 * joystick directions and trigger, and sends JOYSTICK/CONSOLE_KEYS messages
 * via the AESP client. Only sends when state changes to avoid flooding the
 * WebSocket connection.
 *
 * Usage:
 *   const handler = new GamepadHandler(client, (n) => ui.setGamepadCount(n));
 *   handler.attach();   // Start listening
 *   handler.detach();   // Stop and clean up
 */
export class GamepadHandler {
  private client: AESPClient;
  private onGamepadChange?: (connected: number) => void;
  private onStateChange?: (state: JoystickState) => void;

  /** Per-port joystick state from the previous poll (for change detection). */
  private portState: [JoystickState, JoystickState] = [neutralJoystick(), neutralJoystick()];

  /** Console key state from the previous poll (shared across all controllers). */
  private consoleState: ConsoleKeyState = neutralConsole();

  /** requestAnimationFrame handle for the polling loop. */
  private pollHandle: number | null = null;

  /** Bound event handler references for cleanup. */
  private onConnected: (e: GamepadEvent) => void;
  private onDisconnected: (e: GamepadEvent) => void;

  constructor(
    client: AESPClient,
    onGamepadChange?: (connected: number) => void,
    onStateChange?: (state: JoystickState) => void,
  ) {
    this.client = client;
    this.onGamepadChange = onGamepadChange;
    this.onStateChange = onStateChange;

    // Bind event handlers so we can remove them in detach()
    this.onConnected = (e) => this.gamepadConnected(e);
    this.onDisconnected = (e) => this.gamepadDisconnected(e);
  }

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /** Starts gamepad discovery and the polling loop. */
  attach(): void {
    window.addEventListener('gamepadconnected', this.onConnected);
    window.addEventListener('gamepaddisconnected', this.onDisconnected);

    // Check for already-connected gamepads (e.g. page refresh with
    // controller plugged in — the browser remembers them).
    this.updateGamepadCount();

    // Start the polling loop
    this.startPolling();
  }

  /** Stops polling, removes listeners, and resets all ports to neutral. */
  detach(): void {
    window.removeEventListener('gamepadconnected', this.onConnected);
    window.removeEventListener('gamepaddisconnected', this.onDisconnected);

    this.stopPolling();
    this.resetAllPorts();
  }

  // -------------------------------------------------------------------------
  // Connection events
  // -------------------------------------------------------------------------

  private gamepadConnected(e: GamepadEvent): void {
    const gp = e.gamepad;
    const mapping = gp.mapping === 'standard' ? 'standard' : 'non-standard';
    console.log(`[Gamepad] Connected: "${gp.id}" (index ${gp.index}, ${mapping})`);
    this.updateGamepadCount();
  }

  private gamepadDisconnected(e: GamepadEvent): void {
    const gp = e.gamepad;
    console.log(`[Gamepad] Disconnected: "${gp.id}" (index ${gp.index})`);

    // Reset the port this controller was on
    const port = gp.index;
    if (port < MAX_PORTS) {
      this.portState[port] = neutralJoystick();
      this.client.sendJoystick(port, false, false, false, false, false);
      if (port === 0) {
        this.onStateChange?.(this.portState[0]);
      }
    }

    this.updateGamepadCount();
  }

  /** Counts connected gamepads and notifies the UI callback. */
  private updateGamepadCount(): void {
    const gamepads = navigator.getGamepads();
    let count = 0;
    for (const gp of gamepads) {
      if (gp && gp.connected) count++;
    }
    this.onGamepadChange?.(count);
  }

  // -------------------------------------------------------------------------
  // Polling loop
  // -------------------------------------------------------------------------

  private startPolling(): void {
    const poll = () => {
      this.pollGamepads();
      this.pollHandle = requestAnimationFrame(poll);
    };
    this.pollHandle = requestAnimationFrame(poll);
  }

  private stopPolling(): void {
    if (this.pollHandle !== null) {
      cancelAnimationFrame(this.pollHandle);
      this.pollHandle = null;
    }
  }

  /**
   * Reads all connected gamepads and sends input changes.
   *
   * Called once per animation frame (~60Hz). For each gamepad mapped to
   * an Atari port (index 0 or 1), reads input using the appropriate
   * mapping (standard or non-standard) and sends only when changed.
   */
  private pollGamepads(): void {
    const gamepads = navigator.getGamepads();

    // Aggregate console keys across all connected controllers
    let newConsole = neutralConsole();

    for (let i = 0; i < Math.min(gamepads.length, MAX_PORTS); i++) {
      const gp = gamepads[i];
      if (!gp || !gp.connected) continue;

      // Read joystick state using the appropriate mapping
      let newState: JoystickState;
      let consoleFromPad: ConsoleKeyState;

      if (gp.mapping === 'standard') {
        [newState, consoleFromPad] = this.readStandardMapping(gp);
      } else {
        [newState, consoleFromPad] = this.readNonStandardMapping(gp);
      }

      // Send joystick state if changed
      if (!joystickEqual(newState, this.portState[i])) {
        this.portState[i] = newState;
        this.client.sendJoystick(i, newState.up, newState.down, newState.left, newState.right, newState.trigger);
        // Notify UI of port 0 state for the joystick overlay
        if (i === 0) {
          this.onStateChange?.(newState);
        }
      }

      // OR console keys across all controllers (any pad can press START)
      newConsole.start = newConsole.start || consoleFromPad.start;
      newConsole.select = newConsole.select || consoleFromPad.select;
      newConsole.option = newConsole.option || consoleFromPad.option;
    }

    // Send console keys if changed
    if (!consoleEqual(newConsole, this.consoleState)) {
      this.consoleState = newConsole;
      this.client.sendConsoleKeys(newConsole.start, newConsole.select, newConsole.option);
    }
  }

  // -------------------------------------------------------------------------
  // Input mapping — Standard gamepads (Xbox, PS, MFi)
  // -------------------------------------------------------------------------

  /**
   * Reads input from a standard-mapped gamepad.
   *
   * Standard mapping (W3C Gamepad spec):
   *   buttons[0]  = A/Cross        → Fire
   *   buttons[1]  = B/Circle       → Fire
   *   buttons[4]  = LB/L1          → OPTION
   *   buttons[7]  = RT/R2          → Fire
   *   buttons[8]  = Back/Select    → SELECT
   *   buttons[9]  = Start/Menu     → START
   *   buttons[12] = D-pad Up       → Up
   *   buttons[13] = D-pad Down     → Down
   *   buttons[14] = D-pad Left     → Left
   *   buttons[15] = D-pad Right    → Right
   *   axes[0]     = Left stick X   → Left/Right (with deadzone)
   *   axes[1]     = Left stick Y   → Up/Down (with deadzone)
   */
  private readStandardMapping(gp: Gamepad): [JoystickState, ConsoleKeyState] {
    // D-pad buttons (digital)
    const dpadUp    = this.btn(gp, 12);
    const dpadDown  = this.btn(gp, 13);
    const dpadLeft  = this.btn(gp, 14);
    const dpadRight = this.btn(gp, 15);

    // Left stick (analog with deadzone)
    const stickX = gp.axes[0] ?? 0;
    const stickY = gp.axes[1] ?? 0;

    const joystick: JoystickState = {
      up:      dpadUp    || stickY < -DEADZONE,
      down:    dpadDown  || stickY > DEADZONE,
      left:    dpadLeft  || stickX < -DEADZONE,
      right:   dpadRight || stickX > DEADZONE,
      trigger: this.btn(gp, 0) || this.btn(gp, 1) || this.btn(gp, 7),
    };

    // Console keys: Menu→START, Back→SELECT, LB→OPTION
    const console: ConsoleKeyState = {
      start:  this.btn(gp, 9),
      select: this.btn(gp, 8),
      option: this.btn(gp, 4),
    };

    return [joystick, console];
  }

  // -------------------------------------------------------------------------
  // Input mapping — Non-standard gamepads (CX Stick, retro joysticks)
  // -------------------------------------------------------------------------

  /**
   * Reads input from a non-standard (generic HID) gamepad.
   *
   * Generic HID joysticks typically report:
   *   axes[0] = X axis (left/right)
   *   axes[1] = Y axis (up/down)
   *   buttons[0] = primary fire button
   *
   * This mirrors HIDJoystickManager.swift which normalizes raw HID axes
   * and maps any button press to trigger.
   */
  private readNonStandardMapping(gp: Gamepad): [JoystickState, ConsoleKeyState] {
    // Axes with deadzone (same normalization as HIDJoystickManager)
    const axisX = gp.axes[0] ?? 0;
    const axisY = gp.axes[1] ?? 0;

    // Any button counts as trigger (CX Stick has just one fire button,
    // but other generic joysticks may have more)
    let trigger = false;
    for (let i = 0; i < gp.buttons.length; i++) {
      if (gp.buttons[i].pressed) {
        trigger = true;
        break;
      }
    }

    const joystick: JoystickState = {
      up:    axisY < -DEADZONE,
      down:  axisY > DEADZONE,
      left:  axisX < -DEADZONE,
      right: axisX > DEADZONE,
      trigger,
    };

    // No console key mapping for generic joysticks (not enough buttons)
    return [joystick, neutralConsole()];
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /** Safely reads a button's pressed state (false if index out of range). */
  private btn(gp: Gamepad, index: number): boolean {
    return index < gp.buttons.length && gp.buttons[index].pressed;
  }

  /** Sends neutral (centered, no trigger) state for both ports. */
  private resetAllPorts(): void {
    for (let port = 0; port < MAX_PORTS; port++) {
      this.portState[port] = neutralJoystick();
      this.client.sendJoystick(port, false, false, false, false, false);
    }
    this.consoleState = neutralConsole();
    this.client.sendConsoleKeys(false, false, false);
  }
}
