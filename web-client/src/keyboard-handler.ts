// =============================================================================
// keyboard-handler.ts — Browser keyboard to Atari key mapping
// =============================================================================
//
// Maps KeyboardEvent.code (physical key position) to Atari AKEY codes and
// ATASCII character values. Uses .code instead of .key because the Atari's
// keyboard matrix is position-based, matching physical key locations.
//
// Key event flow:
//   Browser KeyDown → map to (keyChar, keyCode, shift, control) → KEY_DOWN msg
//   Browser KeyUp   → KEY_UP msg (releases current key)
//
// Console keys (F1=START, F2=SELECT, F3=OPTION) are sent as CONSOLE_KEYS
// messages, not KEY_DOWN, because the Atari treats them as latching switches.
// =============================================================================

import { AESPClient } from './aesp-client';

// ---------------------------------------------------------------------------
// AKEY constants (from libatari800.h)
// ---------------------------------------------------------------------------

/** Sentinel value meaning "use keyChar, not keyCode". */
const AKEY_NONE = 0xFF;

const AKEY_RETURN    = 0x0C;
const AKEY_ESCAPE    = 0x1C;
const AKEY_TAB       = 0x2C;
const AKEY_BACKSPACE = 0x34;
const AKEY_SPACE     = 0x21;
const AKEY_UP        = 0x8E;
const AKEY_DOWN      = 0x8F;
const AKEY_LEFT      = 0x86;
const AKEY_RIGHT     = 0x87;
const AKEY_ATARI     = 0x27;
const AKEY_CAPSTOGGLE = 0x3C;
const AKEY_HELP      = 0x11;

// ---------------------------------------------------------------------------
// Key mapping tables
// ---------------------------------------------------------------------------

/**
 * Special keys: maps KeyboardEvent.code to [keyChar, keyCode].
 * These keys use the keyCode field (not keyChar) in the KEY_DOWN payload.
 */
const SPECIAL_KEYS: Record<string, [number, number]> = {
  'Enter':       [0, AKEY_RETURN],
  'NumpadEnter': [0, AKEY_RETURN],
  'Escape':      [0, AKEY_ESCAPE],
  'Tab':         [0, AKEY_TAB],
  'Backspace':   [0, AKEY_BACKSPACE],
  'Space':       [0x20, AKEY_SPACE],
  'ArrowUp':     [0, AKEY_UP],
  'ArrowDown':   [0, AKEY_DOWN],
  'ArrowLeft':   [0, AKEY_LEFT],
  'ArrowRight':  [0, AKEY_RIGHT],
  'Backquote':   [0, AKEY_ATARI],
  'CapsLock':    [0, AKEY_CAPSTOGGLE],
  'F4':          [0, AKEY_HELP],
};

/**
 * Console keys: maps KeyboardEvent.code to which console key flag to set.
 * These are sent as CONSOLE_KEYS messages, not KEY_DOWN.
 */
const CONSOLE_KEY_MAP: Record<string, 'start' | 'select' | 'option'> = {
  'F1': 'start',
  'F2': 'select',
  'F3': 'option',
};

// ---------------------------------------------------------------------------
// KeyboardHandler
// ---------------------------------------------------------------------------

/**
 * Handles browser keyboard events and sends Atari key messages.
 *
 * Listens for keydown/keyup on a target element (usually the canvas) and
 * maps them to AESP KEY_DOWN, KEY_UP, and CONSOLE_KEYS messages.
 *
 * Call `attach()` to start listening and `detach()` to stop.
 */
export class KeyboardHandler {
  private client: AESPClient;
  private target: HTMLElement;

  // Console key state (latching — stays active while held)
  private consoleState = { start: false, select: false, option: false };

  // Bound event handlers (for detach)
  private onKeyDown: (e: KeyboardEvent) => void;
  private onKeyUp: (e: KeyboardEvent) => void;
  private onBlur: () => void;

  constructor(client: AESPClient, target: HTMLElement) {
    this.client = client;
    this.target = target;

    this.onKeyDown = this.handleKeyDown.bind(this);
    this.onKeyUp = this.handleKeyUp.bind(this);
    this.onBlur = this.handleBlur.bind(this);
  }

  /** Start listening for keyboard events on the target element. */
  attach(): void {
    this.target.addEventListener('keydown', this.onKeyDown);
    this.target.addEventListener('keyup', this.onKeyUp);
    window.addEventListener('blur', this.onBlur);
  }

  /** Stop listening for keyboard events. */
  detach(): void {
    this.target.removeEventListener('keydown', this.onKeyDown);
    this.target.removeEventListener('keyup', this.onKeyUp);
    window.removeEventListener('blur', this.onBlur);
  }

  // -------------------------------------------------------------------------
  // Event handlers
  // -------------------------------------------------------------------------

  private handleKeyDown(e: KeyboardEvent): void {
    // Ignore auto-repeat — the Atari doesn't have key repeat in the same way
    if (e.repeat) return;

    // Console keys (F1/F2/F3) are handled separately
    const consoleKey = CONSOLE_KEY_MAP[e.code];
    if (consoleKey) {
      e.preventDefault();
      this.consoleState[consoleKey] = true;
      this.client.sendConsoleKeys(
        this.consoleState.start,
        this.consoleState.select,
        this.consoleState.option,
      );
      return;
    }

    // Special keys (arrows, enter, escape, etc.)
    const special = SPECIAL_KEYS[e.code];
    if (special) {
      e.preventDefault();
      const [keyChar, keyCode] = special;
      this.client.sendKeyDown(keyChar, keyCode, e.shiftKey, e.ctrlKey);
      return;
    }

    // Letter keys (KeyA through KeyZ)
    if (e.code.startsWith('Key') && e.code.length === 4) {
      e.preventDefault();
      const letter = e.code.charAt(3); // 'A' through 'Z'

      if (e.ctrlKey) {
        // Ctrl+A through Ctrl+Z → ATASCII 0x01-0x1A
        const keyChar = letter.charCodeAt(0) - 0x40;
        this.client.sendKeyDown(keyChar, AKEY_NONE, e.shiftKey, true);
        return;
      }

      // libatari800 maps 'A'→AKEY_A (UPPERCASE on screen) and
      // 'a'→AKEY_a (lowercase on screen). The Atari keyboard is inverted
      // from modern keyboards (no shift = uppercase, shift = lowercase).
      // e.code always gives uppercase, so invert when shift or caps lock
      // is active (XOR) to produce lowercase on the Atari.
      const capsLock = e.getModifierState('CapsLock');
      const wantLowercase = capsLock !== e.shiftKey; // XOR
      const keyChar = wantLowercase
        ? letter.toLowerCase().charCodeAt(0)
        : letter.charCodeAt(0);

      this.client.sendKeyDown(keyChar, AKEY_NONE, e.shiftKey, e.ctrlKey);
      return;
    }

    // Digit keys (Digit0 through Digit9)
    if (e.code.startsWith('Digit') && e.code.length === 6) {
      e.preventDefault();
      const digit = e.code.charAt(5); // '0' through '9'

      if (e.shiftKey) {
        // Shifted digits produce punctuation — use event.key for the character
        const shiftedChar = e.key;
        if (shiftedChar.length === 1) {
          this.client.sendKeyDown(shiftedChar.charCodeAt(0), AKEY_NONE, true, e.ctrlKey);
        }
      } else {
        this.client.sendKeyDown(digit.charCodeAt(0), AKEY_NONE, false, e.ctrlKey);
      }
      return;
    }

    // Punctuation and other keys — use event.key if it's a single character
    if (e.key.length === 1 && !e.ctrlKey && !e.metaKey) {
      e.preventDefault();
      this.client.sendKeyDown(e.key.charCodeAt(0), AKEY_NONE, e.shiftKey, false);
      return;
    }
  }

  private handleKeyUp(e: KeyboardEvent): void {
    // Console key release
    const consoleKey = CONSOLE_KEY_MAP[e.code];
    if (consoleKey) {
      e.preventDefault();
      this.consoleState[consoleKey] = false;
      this.client.sendConsoleKeys(
        this.consoleState.start,
        this.consoleState.select,
        this.consoleState.option,
      );
      return;
    }

    // All other key releases send KEY_UP
    e.preventDefault();
    this.client.sendKeyUp();
  }

  /** Release all keys when the window loses focus (prevents stuck keys). */
  private handleBlur(): void {
    this.client.sendKeyUp();
    this.consoleState = { start: false, select: false, option: false };
    this.client.sendConsoleKeys(false, false, false);
  }
}
