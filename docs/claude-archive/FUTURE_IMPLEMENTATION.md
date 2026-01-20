# Future Implementation

This document tracks features that were deferred during the MVP implementation (Phases 1-16) and describes future phases (17-19) for the Attic Emulator project.

## Table of Contents

1. [Deferred Features from MVP](#deferred-features-from-mvp)
2. [Phase 17: Polish & Integration](#phase-17-polish--integration)
3. [Phase 18: WebSocket Bridge](#phase-18-websocket-bridge)
4. [Phase 19: Web Browser Client](#phase-19-web-browser-client)
5. [Implementation Priority](#implementation-priority)

---

## Deferred Features from MVP

The following features were deferred during Phases 1-16 to maintain focus on core functionality.

### Input Handling (Phase 5)

#### Game Controller Support
- **Status:** Not implemented
- **Description:** Add support for game controllers via GameController framework
- **Scope:**
  - GameController framework setup and detection
  - D-pad and analog stick mapping to joystick
  - Button mapping (A=Fire, B=Space, Start=START, etc.)
  - Controller connect/disconnect handling
  - Multiple controller support (ports 1-4)
- **Files to Create/Modify:**
  - `Sources/AtticCore/Input/GameControllerHandler.swift` (new)
  - `Sources/AtticGUI/AtticApp.swift` (add controller initialization)

### AtticServer (Phase 7)

#### Drives Command
- **File:** `Sources/AtticServer/main.swift:432`
- **Status:** Stub returns "drives (none)"
- **Required:** Query DiskManager for actually mounted drives

#### Screenshot Capture
- **File:** `Sources/AtticServer/main.swift:467`
- **Status:** Command accepted but not implemented
- **Required:** Capture frame buffer and save as PNG file
- **Implementation:**
  ```swift
  func captureScreenshot(to path: String) async throws {
      let frameBuffer = await emulator.getFrameBuffer()
      let image = createPNGImage(from: frameBuffer, width: 384, height: 240)
      try image.write(to: URL(fileURLWithPath: path))
  }
  ```

#### BASIC Injection
- **File:** `Sources/AtticServer/main.swift:473`
- **Status:** Validates base64 but doesn't inject
- **Required:** Use BASICMemoryLayout to inject tokenized BASIC into emulator memory

#### Keyboard Injection
- **File:** `Sources/AtticServer/main.swift:480`
- **Status:** Acknowledges but doesn't process
- **Required:** Buffer keystrokes and inject them into the emulator input queue

### AtticCLI (Phase 9)

#### Go Command with PC Setting
- **File:** `Sources/AtticCLI/main.swift:405`
- **Status:** Translates to "resume" without setting PC
- **Required:** Parse address argument and set PC before resume

#### Disassemble Command in CLI
- **File:** `Sources/AtticCLI/main.swift:419`
- **Status:** Command marked as not implemented in translator
- **Required:** Forward to server's disassemble command

### AtticGUI (Phase 8)

#### File Open Handler
- **File:** `Sources/AtticGUI/AtticApp.swift:158`
- **Status:** Stub for double-click handling
- **Required:** Handle .atr files (mount) and .attic files (load state)

#### Open Disk Image Menu
- **File:** `Sources/AtticGUI/AtticApp.swift:806`
- **Status:** Menu item has no action
- **Required:** Present NSOpenPanel filtered for .atr files

#### Save State Menu
- **File:** `Sources/AtticGUI/AtticApp.swift:813`
- **Status:** Menu item has no action
- **Required:** Present NSSavePanel and call state persistence

#### Load State Menu
- **File:** `Sources/AtticGUI/AtticApp.swift:818`
- **Status:** Menu item has no action
- **Required:** Present NSOpenPanel filtered for .attic files

#### Window Scaling
- **File:** `Sources/AtticGUI/AtticApp.swift:860-872`
- **Status:** Three menu items (1x, 2x, 3x) have no action
- **Required:** Resize window to 384×240 multiplied by scale factor

### REPL Engine

#### Screenshot Capture
- **File:** `Sources/AtticCore/REPL/REPLEngine.swift:158`
- **Status:** Returns success without capturing
- **Required:** Call screenshot capture via GUI or embedded emulator

#### Shutdown Signal
- **File:** `Sources/AtticCore/REPL/REPLEngine.swift:207`
- **Status:** Doesn't signal GUI to exit
- **Required:** Send shutdown command to GUI via socket

#### BASIC Renumber
- **File:** `Sources/AtticCore/REPL/REPLEngine.swift:357-358`
- **Status:** Explicitly deferred - complex operation
- **Required:**
  1. Read all BASIC lines from memory
  2. Renumber lines with new start/step values
  3. Update all line number references (GOTO, GOSUB, etc.)
  4. Rewrite program to memory
- **Complexity:** High - requires parsing line references in statements

#### Cross-Drive File Copy
- **File:** `Sources/AtticCore/REPL/REPLEngine.swift:609`
- **Status:** Marked as placeholder
- **Required:** Copy files between different mounted drives

#### Disk Format Confirmation
- **File:** `Sources/AtticCore/REPL/REPLEngine.swift:724`
- **Status:** No user confirmation dialog
- **Required:** Add confirmation prompt before destructive format operation

#### Topic-Specific Help
- **File:** `Sources/AtticCore/REPL/REPLEngine.swift:801`
- **Status:** Returns generic "not available"
- **Required:** Implement help text for individual commands

#### Status Disk Display
- **File:** `Sources/AtticCore/REPL/REPLEngine.swift:869`
- **Status:** Doesn't show mounted disks
- **Required:** Add D1=..., D2=..., etc. to status output

### Monitor Controller

#### Breakpoint Write Tracking
- **File:** `Sources/AtticCore/Monitor/MonitorController.swift:245`
- **Status:** Writing to breakpoint address doesn't update tracked byte
- **Required:** Update original byte tracking when writing to breakpointed address

### CLI Protocol

#### Breakpoint Event Register Parsing
- **File:** `Sources/AtticCore/CLI/CLIProtocol.swift:815`
- **Status:** Only extracts address, returns zero registers
- **Required:** Parse A, X, Y, S, P values from breakpoint event data

---

## Phase 17: Polish & Integration

**Goal:** Production-ready native application.

### Tasks

#### 1. Menu Bar Implementation
- Implement all menu item actions:
  - File menu: Open Disk, Save/Load State, Screenshot
  - Emulator menu: Run, Pause, Reset, Drive submenus
  - View menu: Window scaling (1x, 2x, 3x), Full Screen
- Add keyboard shortcuts for all actions
- Implement Recent Files submenu

#### 2. File Dialogs
```swift
// Open disk image
func openDiskImage() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.init(filenameExtension: "atr")!]
    panel.begin { response in
        if response == .OK, let url = panel.url {
            Task { await self.mountDisk(url, drive: 1) }
        }
    }
}

// Save state
func saveState() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.init(filenameExtension: "attic")!]
    panel.begin { response in
        if response == .OK, let url = panel.url {
            Task { try await self.emulator.saveState(to: url) }
        }
    }
}
```

#### 3. Screenshot Implementation
- Capture Metal texture content
- Convert to PNG using Core Graphics
- Save to user-specified or default path

#### 4. Preferences Window
- ROM path configuration
- Audio settings (volume, enable/disable)
- Video settings (scaling mode, scanlines)
- Key binding customization
- Persist settings using UserDefaults or JSON file

#### 5. Recent Files
- Track recently opened disk images and state files
- Store in UserDefaults
- Display in File > Recent submenu
- Clear recent items option

#### 6. Error Handling Polish
- User-friendly error dialogs for common issues
- Suggestions for resolution
- Log file for debugging

#### 7. Emacs Integration (attic-mode.el)
```elisp
;; Major mode for Attic emulator REPL
(define-derived-mode attic-mode comint-mode "Attic"
  "Major mode for Attic emulator REPL."
  (setq comint-prompt-regexp "^\\[.+\\] .+> ")
  (setq comint-input-sender 'attic-simple-send))

(defun attic ()
  "Start Attic emulator REPL."
  (interactive)
  (make-comint "attic" "attic" nil "--repl")
  (switch-to-buffer "*attic*")
  (attic-mode))

;; Key bindings
(define-key attic-mode-map (kbd "C-c C-r") 'attic-run)
(define-key attic-mode-map (kbd "C-c C-p") 'attic-pause)
(define-key attic-mode-map (kbd "C-c C-s") 'attic-step)
```

#### 8. Documentation
- User guide with screenshots
- Command reference
- Troubleshooting guide

#### 9. App Bundle Polish
- Application icon (multiple resolutions)
- Complete Info.plist with UTI declarations
- Code signing for distribution
- DMG installer creation

### Deliverables
- Complete, polished native application
- Emacs integration package
- User documentation

---

## Phase 18: WebSocket Bridge

**Goal:** Enable web browser clients to connect to the emulator server.

### Background

WebSocket provides a standard way for web browsers to maintain persistent connections. This phase adds a WebSocket bridge that translates between the binary AESP protocol and WebSocket frames.

### Architecture

```
┌─────────────────────────────────────┐
│        AtticServer                  │
│    (AESP on ports 47800-47802)      │
└───────────────┬─────────────────────┘
                │
    ┌───────────┴───────────┐
    │                       │
┌───▼───────────────┐   ┌───▼───────────────┐
│  Native Clients   │   │  WebSocket Bridge │
│  (TCP direct)     │   │  Port 47803       │
└───────────────────┘   └───────┬───────────┘
                                │
                        ┌───────▼───────┐
                        │  Web Browser  │
                        │  Clients      │
                        └───────────────┘
```

### Tasks

#### 1. WebSocket Server
```swift
actor WebSocketBridge {
    private var webSocketListener: NWListener?
    private var webClients: [UUID: WebSocketClient] = [:]
    private var aespClient: AESPClient?

    func start(port: Int = 47803) async throws {
        // Create WebSocket listener
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let wsOptions = NWProtocolWebSocket.Options()
        parameters.defaultProtocolStack.applicationProtocols
            .insert(wsOptions, at: 0)

        webSocketListener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: UInt16(port))!)

        // Connect to AESP server
        aespClient = AESPClient(host: "localhost")
        try await aespClient?.connect()
    }

    func stop() async {
        webSocketListener?.cancel()
        await aespClient?.disconnect()
    }
}
```

#### 2. Protocol Translation
- AESP binary messages pass through directly over WebSocket binary frames
- No transcoding needed - same 8-byte header + payload format
- WebSocket handles framing automatically

#### 3. Video Optimization for Web
```swift
// Delta encoding: only send changed pixels
struct DeltaEncoder {
    private var previousFrame: [UInt8]?

    mutating func encode(_ frame: [UInt8]) -> Data {
        guard let previous = previousFrame else {
            previousFrame = frame
            return Data(frame) // Full frame first time
        }

        var changes: [(index: Int, bgra: [UInt8])] = []
        for i in stride(from: 0, to: frame.count, by: 4) {
            if frame[i..<i+4] != previous[i..<i+4] {
                changes.append((i / 4, Array(frame[i..<i+4])))
            }
        }

        previousFrame = frame
        return encodeDelta(changes)
    }
}
```

#### 4. Audio Handling
- Raw PCM samples sent as binary WebSocket messages
- Client-side Web Audio API handles playback
- Include frame number for A/V synchronization

#### 5. Integration with AtticServer
- WebSocket bridge can run:
  - As part of AtticServer process
  - As separate bridge process
- Command-line flag: `--websocket` to enable

### Testing

- Connect from browser JavaScript console
- Verify binary frames received correctly
- Test video frame delivery
- Test audio sample delivery
- Multiple browser tabs connected simultaneously

### Deliverables

- WebSocket bridge functional
- Ready for web client development

---

## Phase 19: Web Browser Client

**Goal:** Full web-based emulator client running in browser.

### Project Structure

```
web-client/
├── package.json
├── tsconfig.json
├── webpack.config.js
├── src/
│   ├── index.html
│   ├── main.ts
│   ├── style.css
│   ├── protocol/
│   │   ├── AESPClient.ts      # WebSocket client
│   │   └── messages.ts         # Message types
│   ├── video/
│   │   ├── renderer.ts         # Canvas/WebGL renderer
│   │   └── palette.ts          # NTSC color palette
│   ├── audio/
│   │   ├── player.ts           # Web Audio API player
│   │   └── ringbuffer.ts       # Audio buffer management
│   └── input/
│       ├── keyboard.ts         # Browser keyboard mapping
│       └── touch.ts            # Touch input for mobile
└── dist/                        # Built output
```

### Tasks

#### 1. TypeScript Protocol Client
```typescript
class AESPClient {
    private ws: WebSocket | null = null;
    private frameCallback: ((buffer: Uint8Array) => void) | null = null;
    private audioCallback: ((samples: Int16Array) => void) | null = null;

    constructor(private wsUrl: string = 'ws://localhost:47803') {}

    async connect(): Promise<void> {
        return new Promise((resolve, reject) => {
            this.ws = new WebSocket(this.wsUrl);
            this.ws.binaryType = 'arraybuffer';

            this.ws.onopen = () => resolve();
            this.ws.onerror = (e) => reject(e);
            this.ws.onmessage = (e) => this.handleMessage(e.data);
        });
    }

    private handleMessage(data: ArrayBuffer): void {
        const view = new DataView(data);
        const magic = view.getUint16(0);
        if (magic !== 0xAE50) return;

        const type = view.getUint8(3);
        const length = view.getUint32(4);
        const payload = new Uint8Array(data, 8, length);

        switch (type) {
            case 0x60: // FRAME_RAW
                this.frameCallback?.(payload);
                break;
            case 0x80: // AUDIO_PCM
                const samples = new Int16Array(payload.buffer, payload.byteOffset, payload.length / 2);
                this.audioCallback?.(samples);
                break;
        }
    }

    sendKeyDown(keyChar: number, keyCode: number, shift: boolean, ctrl: boolean): void {
        const msg = this.buildMessage(0x40, new Uint8Array([
            keyChar, keyCode, (shift ? 1 : 0) | (ctrl ? 2 : 0)
        ]));
        this.ws?.send(msg);
    }

    sendKeyUp(): void {
        this.ws?.send(this.buildMessage(0x41, new Uint8Array(0)));
    }

    private buildMessage(type: number, payload: Uint8Array): ArrayBuffer {
        const buffer = new ArrayBuffer(8 + payload.length);
        const view = new DataView(buffer);
        view.setUint16(0, 0xAE50); // Magic
        view.setUint8(2, 0x01);     // Version
        view.setUint8(3, type);
        view.setUint32(4, payload.length);
        new Uint8Array(buffer, 8).set(payload);
        return buffer;
    }

    onFrame(callback: (buffer: Uint8Array) => void): void {
        this.frameCallback = callback;
    }

    onAudio(callback: (samples: Int16Array) => void): void {
        this.audioCallback = callback;
    }
}
```

#### 2. Video Rendering
```typescript
class VideoRenderer {
    private canvas: HTMLCanvasElement;
    private ctx: CanvasRenderingContext2D;
    private imageData: ImageData;

    constructor(canvasId: string) {
        this.canvas = document.getElementById(canvasId) as HTMLCanvasElement;
        this.canvas.width = 384;
        this.canvas.height = 240;
        this.ctx = this.canvas.getContext('2d')!;
        this.imageData = this.ctx.createImageData(384, 240);
    }

    renderFrame(bgra: Uint8Array): void {
        // Convert BGRA to RGBA
        const data = this.imageData.data;
        for (let i = 0; i < bgra.length; i += 4) {
            data[i]     = bgra[i + 2]; // R
            data[i + 1] = bgra[i + 1]; // G
            data[i + 2] = bgra[i];     // B
            data[i + 3] = 255;          // A
        }
        this.ctx.putImageData(this.imageData, 0, 0);
    }
}
```

#### 3. Audio Playback
```typescript
class AudioPlayer {
    private audioContext: AudioContext | null = null;
    private scriptNode: ScriptProcessorNode | null = null;
    private ringBuffer: Float32Array;
    private writeIndex = 0;
    private readIndex = 0;

    constructor(bufferSize: number = 16384) {
        this.ringBuffer = new Float32Array(bufferSize);
    }

    start(): void {
        this.audioContext = new AudioContext({ sampleRate: 44100 });
        this.scriptNode = this.audioContext.createScriptProcessor(1024, 0, 1);

        this.scriptNode.onaudioprocess = (e) => {
            const output = e.outputBuffer.getChannelData(0);
            for (let i = 0; i < output.length; i++) {
                output[i] = this.ringBuffer[this.readIndex];
                this.readIndex = (this.readIndex + 1) % this.ringBuffer.length;
            }
        };

        this.scriptNode.connect(this.audioContext.destination);
    }

    enqueueSamples(samples: Int16Array): void {
        for (let i = 0; i < samples.length; i++) {
            this.ringBuffer[this.writeIndex] = samples[i] / 32768.0;
            this.writeIndex = (this.writeIndex + 1) % this.ringBuffer.length;
        }
    }

    stop(): void {
        this.scriptNode?.disconnect();
        this.audioContext?.close();
    }
}
```

#### 4. Keyboard Input
```typescript
class KeyboardHandler {
    private client: AESPClient;

    // Mac keyCode to Atari AKEY mapping
    private keyMap: Map<string, [number, number]> = new Map([
        ['KeyA', [0x61, 0x3F]],
        ['KeyB', [0x62, 0x15]],
        // ... full mapping
        ['Enter', [0x9B, 0x0C]],
        ['Backspace', [0x7E, 0x34]],
    ]);

    constructor(client: AESPClient) {
        this.client = client;
        document.addEventListener('keydown', (e) => this.handleKeyDown(e));
        document.addEventListener('keyup', (e) => this.handleKeyUp(e));
    }

    private handleKeyDown(e: KeyboardEvent): void {
        e.preventDefault();
        const mapping = this.keyMap.get(e.code);
        if (mapping) {
            this.client.sendKeyDown(mapping[0], mapping[1], e.shiftKey, e.ctrlKey);
        }
    }

    private handleKeyUp(e: KeyboardEvent): void {
        e.preventDefault();
        this.client.sendKeyUp();
    }
}
```

#### 5. UI Features
- Fullscreen toggle button
- Mute/unmute audio button
- Connection status indicator
- On-screen keyboard for mobile devices
- Touch controls for mobile joystick emulation

### Browser Compatibility

| Feature | Chrome | Firefox | Safari | Edge |
|---------|--------|---------|--------|------|
| WebSocket | Yes | Yes | Yes | Yes |
| Web Audio | Yes | Yes | Yes | Yes |
| Canvas 2D | Yes | Yes | Yes | Yes |
| Keyboard API | Yes | Yes | Partial | Yes |

### Testing

- Works in Chrome, Firefox, Safari
- Video displays correctly at 60fps
- Audio plays without crackling
- Keyboard input responsive
- Mobile browser support (touch input)
- Multiple users watching same emulator

### Deliverables

- Complete web client
- Can run Atari emulator in browser
- Multiple users can watch same emulator instance

---

## Implementation Priority

### High Priority (Phase 17)
1. Screenshot capture (frequently requested)
2. GUI menu actions (expected functionality)
3. Preferences persistence

### Medium Priority (Phase 17)
4. Game controller support
5. Emacs integration
6. Error handling polish

### Lower Priority (Phases 18-19)
7. WebSocket bridge
8. Web browser client

### Estimated Effort

| Phase | Effort | Dependencies |
|-------|--------|--------------|
| 17 | 3-5 days | None |
| 18 | 2-3 days | Phase 17 |
| 19 | 3-5 days | Phase 18 |

---

## Notes

- All deferred features are tracked with file paths and line numbers for easy location
- Implementation should follow existing patterns in the codebase
- Tests should be added for all new functionality
- Documentation should be updated as features are implemented
