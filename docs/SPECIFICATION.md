# Complete Feature Specification

## 1. Application Bundle

### Bundle Structure

```
Attic.app/
└── Contents/
    ├── Info.plist
    ├── MacOS/
    │   ├── AtticGUI             # Main GUI executable (libatari800 statically linked)
    │   └── attic                # Command-line tool (libatari800 statically linked)
    ├── Resources/
    │   ├── ROM/
    │   │   ├── ATARIXL.ROM      # 16KB OS ROM
    │   │   ├── ATARIBAS.ROM     # 8KB BASIC ROM
    │   │   └── ATARIOSA.ROM     # Optional: OS-A for compatibility
    │   ├── Assets.xcassets
    │   └── Credits.rtf
    └── Library/
        └── LaunchServices/
            └── attic            # For command-line access
```

**Note:** libatari800 is statically linked into both executables rather than distributed
as a dynamic library. This simplifies deployment and eliminates framework path issues.

### Info.plist Requirements

```xml
<key>CFBundleIdentifier</key>
<string>com.example.attic</string>

<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>Atari Disk Image</string>
        <key>CFBundleTypeExtensions</key>
        <array>
            <string>atr</string>
            <string>ATR</string>
        </array>
    </dict>
    <dict>
        <key>CFBundleTypeName</key>
        <string>Attic State</string>
        <key>CFBundleTypeExtensions</key>
        <array>
            <string>attic</string>
        </array>
    </dict>
</array>
```

## 2. GUI Application

### Window Layout

```
┌─────────────────────────────────────────────────────────┐
│  Atari 800 XL                              [–] [□] [×]  │
├─────────────────────────────────────────────────────────┤
│                                                         │
│                                                         │
│                    ┌─────────────────┐                  │
│                    │                 │                  │
│                    │   Atari Screen  │                  │
│                    │   (Metal View)  │                  │
│                    │   384 × 240     │                  │
│                    │   scaled 3×     │                  │
│                    │                 │                  │
│                    └─────────────────┘                  │
│                                                         │
├─────────────────────────────────────────────────────────┤
│  [START] [SELECT] [OPTION]  │  Status: Running  60 FPS  │
└─────────────────────────────────────────────────────────┘
```

### Menu Structure

```
Attic
  About Attic
  Preferences...                    ⌘,
  ───────────────────────────────────
  Quit                              ⌘Q

File
  Open Disk Image...                ⌘O
  Recent Disk Images               ▶
  Close Disk Image
  ───────────────────────────────────
  Save State...                     ⌘S
  Save State As...                  ⌘⇧S
  Load State...                     ⌘L
  ───────────────────────────────────
  Screenshot                        ⌘P
  Screenshot As...                  ⌘⇧P

Emulator
  Run                               ⌘R
  Pause                             ⌘.
  ───────────────────────────────────
  Reset (Cold)                      ⌘⇧R
  Reset (Warm)                      ⌘⌥R
  ───────────────────────────────────
  Drive 1                          ▶
    Insert Disk...
    Eject
    Write Protect
  Drive 2                          ▶
    ...

View
  Actual Size                       ⌘1
  Double Size                       ⌘2
  Triple Size                       ⌘3
  ───────────────────────────────────
  Enter Full Screen                 ⌘⌃F
```

### Keyboard Mapping

| Host Key | Atari Key |
|----------|-----------|
| A-Z | A-Z |
| 0-9 | 0-9 |
| Return | Return |
| Backspace | Delete |
| Tab | Tab |
| Escape | Escape |
| F1 | START |
| F2 | SELECT |
| F3 | OPTION |
| F4 + ⌘ | RESET |
| Shift | Shift |
| Control | Control |
| ` (backtick) | ATARI key |
| Caps Lock | Caps |

### Game Controller Mapping

| Controller | Atari |
|------------|-------|
| D-pad / Left Stick | Joystick directions |
| Button A (South) | Fire button |
| Button B (East) | Space (secondary) |
| Start | START |
| Select/Back | SELECT |
| L1/R1 | OPTION |

### Metal Rendering

- Frame buffer: 384×240 pixels (Atari native resolution with overscan)
- Pixel format: BGRA8Unorm (converted from Atari palette)
- Display scaling: Nearest neighbor for crisp pixels
- Default window size: 1152×720 (3× scale)
- VSync enabled via CADisplayLink

### Audio Output

- Sample rate: 44100 Hz (configurable via libatari800)
- Channels: Mono (POKEY output)
- Sample format: 16-bit signed PCM (converted to Float internally)
- Ring buffer: 8192 samples (~185ms capacity for jitter absorption)
- AVAudioEngine callback buffer: 512-1024 samples
- Typical latency: 50-100ms (acceptable for emulation use case)

**Implementation Notes:**
- libatari800 generates ~735 samples per frame at 60fps
- AudioEngine converts 8-bit or 16-bit PCM to Float for AVAudioEngine
- Larger ring buffer prevents underruns during system load spikes

## 3. CLI Application

### Command-Line Arguments

```
USAGE: attic [options]

OPTIONS:
  --repl              Start in REPL mode (default)
  --headless          Run without launching GUI
  --silent            Disable audio output (headless mode only)
  --socket <path>     Connect to GUI at specific socket path
  --help              Show help information

EXAMPLES:
  attic                                Launch GUI and connect REPL
  attic --headless                     Run emulator without GUI
  attic --socket /tmp/attic-1234.sock  Connect to existing GUI
```

### REPL Prompt Format

Prompts must be recognizable by Emacs comint:

```
[monitor] $E477> 
[basic] > 
[dos] D1:> 
```

The prompt always ends with `> ` followed by a space, making it easy to match with regex: `^\[.+\] .+> $`

## 4. Startup Sequence

### GUI Startup

```
1. Application launch
2. SwiftUI creates AtticApp and AtticViewModel
3. ContentView appears, triggering initialization
4. Locate ROMs (searched in order):
   - ./Resources/ROM/
   - Bundle.main/Contents/Resources/ROM/
   - ~/.attic/ROM/
   - Source directory (for development)
   - If missing: show error overlay in window
5. Initialize libatari800 (via EmulatorEngine actor)
   - Set machine type: Atari 800 XL (-xl flag)
   - Enable BASIC ROM (-basic flag)
   - Enable 16-bit audio (-audio16 flag)
6. Configure and start AudioEngine
   - Query libatari800 for sample rate/format
   - Create AVAudioEngine with AVAudioSourceNode
   - Start audio output
7. Initialize Metal renderer (when MTKView created)
   - Create MTLDevice
   - Compile embedded shaders
   - Create render pipeline and texture
8. Start emulation loop (Task in AtticViewModel)
   - Run at ~60fps using Task.sleep timing
   - Extract video and audio buffers each frame
9. Auto-start emulation (boots to BASIC Ready)
10. Window fully visible with running emulator
```

**Note:** Socket server for CLI communication is implemented in Phase 9 (CLI Socket Protocol).

### CLI Startup (Normal)

```
1. Parse command-line arguments
2. Look for existing socket: /tmp/attic-*.sock
3. If no socket found:
   a. Determine GUI path from bundle
   b. Launch GUI as subprocess (NSTask/Process)
   c. Poll for socket (100ms intervals, 50 tries)
4. Connect to socket
5. Send handshake: CMD:ping
6. Wait for: OK:pong
7. Print welcome banner
8. Enter BASIC mode (default)
9. Begin REPL loop
```

### CLI Startup (Headless)

```
1. Parse command-line arguments
2. Locate ROMs (same path resolution as GUI)
3. Initialize libatari800 directly
4. Initialize audio (unless --silent)
5. Cold start emulator
6. Print welcome banner
7. Enter BASIC mode
8. Begin REPL loop
```

## 5. State Persistence

### Save State Contents

- Complete CPU state (A, X, Y, S, P, PC)
- All 64KB of RAM
- ANTIC, GTIA, POKEY, PIA register states
- Mounted disk image paths (not contents)
- REPL mode and breakpoints (optional)

### State File Format

Using a combination of libatari800's native format and our metadata:

```
┌──────────────────────────────────┐
│ Header (16 bytes)                │
│   Magic: "ATTC" (4 bytes)        │
│   Version: UInt8 (1 byte)        │
│   Flags: UInt8 (1 byte)          │
│   Reserved: (10 bytes)           │
├──────────────────────────────────┤
│ Metadata (JSON, length-prefixed) │
│   - Timestamp                    │
│   - Mounted disks                │
│   - Breakpoints                  │
├──────────────────────────────────┤
│ libatari800 state (opaque blob)  │
└──────────────────────────────────┘
```

### File Extension

- `.attic` - Attic State file

## 6. Screenshot Capability

### Screenshot Command

```
.screenshot              Save to ~/Desktop/Attic-<YYYYMMDD-HHMMSS>.png
.screenshot /path/to.png Save to specific path
```

### Screenshot Format

- PNG format
- Native resolution (384×240) scaled 3×
- No post-processing effects
- sRGB color space

## 7. Disk Image Support

### Supported Formats

- **ATR** - Atari disk image (primary format)
  - Single density: 720 sectors × 128 bytes = 92,160 bytes
  - Enhanced density: 1040 sectors × 128 bytes = 133,120 bytes
  - Double density: 720 sectors × 256 bytes = 184,320 bytes

### Drive Assignments

- D1: through D8: supported
- D1: is the default/current drive
- Auto-boot from D1: if bootable disk present

## 8. Error Handling

### Error Message Format

All errors follow a consistent format:

```
Error [at location]:
  <error message>
  [Suggestion: <helpful suggestion>]
```

### Examples

**Tokenizer Error:**
```
Error at line 10, column 15:
  10 PRINT HELLO
              ^^^^
Unrecognized identifier 'HELLO'
  Suggestion: For a string, use "HELLO". For a variable, it will be created automatically.
```

**Monitor Error:**
```
Error: Invalid address 'GGGG'
  Addresses must be hexadecimal ($0000-$FFFF) or decimal (0-65535)
  Suggestion: Use $GGGG for hex or prefix with $ symbol
```

**DOS Error:**
```
Error: File not found 'NOFILE.DAT'
  No files matching 'NOFILE.DAT' on D1:
  Suggestion: Use 'dir' to list available files
```

**Socket Error:**
```
Error: Cannot connect to Atari 800 XL GUI
  No socket found at /tmp/attic-*.sock
  Suggestion: Launch the GUI application first, or use --headless mode
```
