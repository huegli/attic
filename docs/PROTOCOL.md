# Attic Communication Protocols

This document describes the two communication protocols used by the Attic Emulator:

1. **AESP (Attic Emulator Server Protocol)** - Binary protocol for GUI/web clients
2. **CLI Protocol** - Text-based protocol for REPL/Emacs integration

---

# Part 1: Attic Emulator Server Protocol (AESP)

AESP is a binary protocol for high-performance communication between the emulator server (AtticServer) and GUI/web clients. It supports video streaming at 60fps, audio streaming, and real-time input handling.

## Transport Architecture

```
┌─────────────────────────────────────┐
│        AtticServer                  │
│    (standalone process)             │
└───────────────┬─────────────────────┘
                │
    ┌───────────┼───────────┐
    │           │           │
┌───▼───┐   ┌───▼───┐   ┌───▼───┐
│Control│   │ Video │   │ Audio │
│ :47800│   │ :47801│   │ :47802│
└───┬───┘   └───┬───┘   └───┬───┘
    │           │           │
    └─────────┬─┴───────────┘
              │
      ┌───────┴───────┐
      │               │
┌─────▼─────┐   ┌─────▼─────┐
│Native GUI │   │WebSocket  │
│(SwiftUI)  │   │Bridge     │
└───────────┘   └─────┬─────┘
                      │
                ┌─────▼─────┐
                │Web Browser│
                │  :47803   │
                └───────────┘
```

### Ports

| Port  | Channel   | Data Rate  | Purpose                              |
|-------|-----------|------------|--------------------------------------|
| 47800 | Control   | Low        | Commands, status, input               |
| 47801 | Video     | ~21 MB/s   | Raw BGRA frames (384×240×4 @ 60fps)  |
| 47802 | Audio     | ~88 KB/s   | 16-bit PCM (44.1kHz mono)            |
| 47803 | WebSocket | Variable   | Bridges all channels for web clients |

### Connection Model

- **Control**: Bidirectional TCP - clients send commands, server responds
- **Video**: Push-based TCP - server broadcasts frames to subscribed clients
- **Audio**: Push-based TCP - server broadcasts samples to subscribed clients
- **WebSocket**: Bidirectional - bridges all channels over a single connection

## Binary Message Format

All AESP messages use an 8-byte header followed by a variable-length payload:

```
┌────────┬────────┬────────┬──────────┬─────────────┐
│ Magic  │Version │ Type   │  Length  │  Payload    │
│ 0xAE50 │ 0x01   │(1 byte)│ (4 bytes)│ (variable)  │
└────────┴────────┴────────┴──────────┴─────────────┘
  2 bytes  1 byte   1 byte   4 bytes     N bytes

Total header: 8 bytes
```

### Header Fields

| Field   | Offset | Size    | Format      | Description                                |
|---------|--------|---------|-------------|--------------------------------------------|
| Magic   | 0      | 2 bytes | Big-endian  | Always `0xAE50` ("AE" = Attic Emulator)    |
| Version | 2      | 1 byte  | Unsigned    | Protocol version (currently `0x01`)        |
| Type    | 3      | 1 byte  | Unsigned    | Message type (see below)                   |
| Length  | 4      | 4 bytes | Big-endian  | Payload length in bytes (0 to 16,777,216)  |

### Byte Order

All multi-byte integers use **big-endian** (network) byte order.

### Maximum Message Size

- Maximum payload size: 16 MB (`0x01000000` bytes)
- Typical video frame payload: 368,640 bytes
- Typical audio payload: ~1,470 bytes per frame

## Message Types

Message types are organized by category based on their numeric range:

| Range     | Category | Description                           |
|-----------|----------|---------------------------------------|
| 0x00-0x3F | Control  | Commands, status, errors              |
| 0x40-0x5F | Input    | Keyboard, joystick, console keys      |
| 0x60-0x7F | Video    | Frame data, configuration             |
| 0x80-0x9F | Audio    | PCM samples, sync                     |

### Control Messages (0x00-0x3F)

#### PING (0x00)
Check server is alive.

| Direction | Payload |
|-----------|---------|
| Request   | Empty   |
| Response  | PONG    |

**Test Case**: Send PING, verify PONG received within 1 second.

#### PONG (0x01)
Response to PING.

| Direction | Payload |
|-----------|---------|
| Response  | Empty   |

#### PAUSE (0x02)
Pause emulation.

| Direction | Payload |
|-----------|---------|
| Request   | Empty   |
| Response  | ACK(0x02) |

**Test Case**: Send PAUSE, verify emulation stops (no more FRAME_RAW messages).

#### RESUME (0x03)
Resume emulation.

| Direction | Payload |
|-----------|---------|
| Request   | Empty   |
| Response  | ACK(0x03) |

**Test Case**: After PAUSE, send RESUME, verify FRAME_RAW messages resume.

#### RESET (0x04)
Reset emulator.

| Direction | Payload                                       |
|-----------|-----------------------------------------------|
| Request   | 1 byte: `0x00` = warm reset, `0x01` = cold    |
| Response  | ACK(0x04)                                     |

**Payload Format**:
```
Offset 0: Reset type (1 byte)
  0x00 = Warm reset (preserves RAM)
  0x01 = Cold reset (clears RAM, like power cycle)
```

**Test Cases**:
- Cold reset: Send RESET(0x01), verify boot screen appears
- Warm reset: Send RESET(0x00), verify emulator restarts without full reboot

#### STATUS (0x05)
Query emulator status.

| Direction | Payload                    |
|-----------|----------------------------|
| Request   | Empty                      |
| Response  | Status payload (see below) |

**Response Payload Format**:
```
Offset 0: State (1 byte)
  0x00 = Paused
  0x01 = Running
```

**Test Case**: Send STATUS after PAUSE, verify state byte is 0x00.

#### INFO (0x06)
Query emulator capabilities.

| Direction | Payload                              |
|-----------|--------------------------------------|
| Request   | Empty                                |
| Response  | UTF-8 JSON with version/capabilities |

#### BOOT_FILE (0x07)
Load and boot a file into the emulator.

| Direction | Payload                                      |
|-----------|----------------------------------------------|
| Request   | UTF-8 file path string                       |
| Response  | 1 byte status + UTF-8 message                |

**Request Payload**: UTF-8 encoded absolute file path.

**Response Payload**:
```
Offset 0: Status (1 byte)
  0x00 = Success
  0x01 = Failure
Offset 1-N: UTF-8 status/error message
```

**Supported file types**: ATR, XFD, ATX, DCM, PRO (disk images), XEX/COM/EXE (executables), BAS/LST (BASIC programs), CART/ROM (cartridges), CAS (cassette images).

**Test Case**: Send BOOT_FILE with valid ATR path, verify success response.

#### ACK (0x0F)
Generic acknowledgement.

| Direction | Payload                               |
|-----------|---------------------------------------|
| Response  | 1 byte: message type being acknowledged |

**Payload Format**:
```
Offset 0: Acknowledged message type (1 byte)
```

**Test Case**: Send PAUSE, verify ACK received with payload 0x02.

**Note**: Memory access, register access, and breakpoint management are available through the CLI socket protocol (Part 2), not the AESP binary protocol. AESP focuses on streaming (video/audio) and real-time input.

#### ERROR (0x3F)
Error response from server.

| Direction | Payload                        |
|-----------|--------------------------------|
| Response  | 1 byte code + UTF-8 message    |

**Payload Format**:
```
Offset 0: Error code (1 byte)
Offset 1-N: UTF-8 error message
```

**Error Codes**:
| Code | Meaning               |
|------|-----------------------|
| 0x01 | Invalid command       |
| 0x02 | Invalid address       |
| 0x03 | Invalid payload       |
| 0x04 | Operation failed      |
| 0x05 | Not implemented       |

### Input Messages (0x40-0x5F)

#### KEY_DOWN (0x40)
Key press event.

| Direction | Payload    |
|-----------|------------|
| Request   | 3 bytes    |

**Payload Format**:
```
Offset 0: Key character (ATASCII code, 0 for special keys)
Offset 1: Key code (AKEY_* constant from libatari800)
Offset 2: Modifier flags
  Bit 0: Shift held
  Bit 1: Control held
  Bits 2-7: Reserved
```

**Test Cases**:
- Press 'A': KEY_DOWN(0x41, AKEY_a, 0x00)
- Press Shift+'A': KEY_DOWN(0x41, AKEY_a, 0x01)
- Press Ctrl+'A': KEY_DOWN(0x01, AKEY_a, 0x02)
- Press Return: KEY_DOWN(0x9B, AKEY_RETURN, 0x00)

#### KEY_UP (0x41)
Key release event.

| Direction | Payload |
|-----------|---------|
| Request   | Empty   |

**Note**: Releases the currently pressed key. The Atari only tracks one key at a time.

**Test Case**: Send KEY_DOWN('A'), then KEY_UP, verify key is released in emulator.

#### JOYSTICK (0x42)
Joystick state update.

| Direction | Payload  |
|-----------|----------|
| Request   | 2 bytes  |

**Payload Format**:
```
Offset 0: Port number (0 or 1)
Offset 1: State flags
  Bit 0: Up
  Bit 1: Down
  Bit 2: Left
  Bit 3: Right
  Bit 4: Trigger (fire button)
  Bits 5-7: Reserved
```

**Test Cases**:
- Joystick 1 up: JOYSTICK(0, 0x01)
- Joystick 1 down+trigger: JOYSTICK(0, 0x12)
- Joystick 2 left: JOYSTICK(1, 0x04)
- Joystick 1 neutral: JOYSTICK(0, 0x00)

#### CONSOLE_KEYS (0x43)
Console keys state (START, SELECT, OPTION).

| Direction | Payload |
|-----------|---------|
| Request   | 1 byte  |

**Payload Format**:
```
Offset 0: State flags
  Bit 0: START pressed
  Bit 1: SELECT pressed
  Bit 2: OPTION pressed
  Bits 3-7: Reserved
```

**Test Cases**:
- Press START: CONSOLE_KEYS(0x01)
- Press START+OPTION: CONSOLE_KEYS(0x05)
- Release all: CONSOLE_KEYS(0x00)

#### PADDLE (0x44)
Paddle position update.

| Direction | Payload |
|-----------|---------|
| Request   | 2 bytes |

**Payload Format**:
```
Offset 0: Paddle number (0-3)
Offset 1: Position (0-228)
```

### Video Messages (0x60-0x7F)

#### FRAME_RAW (0x60)
Raw video frame data (server → client).

| Direction | Payload                    |
|-----------|----------------------------|
| Broadcast | 368,640 bytes BGRA pixels  |

**Payload Format**:
```
384 × 240 × 4 = 368,640 bytes
Format: BGRA8888 (Blue, Green, Red, Alpha)
Pixel order: Row-major, top-to-bottom, left-to-right
```

**Video Constants**:
- Width: 384 pixels
- Height: 240 pixels
- Bytes per pixel: 4 (BGRA)
- Frame size: 368,640 bytes
- Frame rate: ~60 fps (NTSC)

**Test Cases**:
- Subscribe to video, verify frame size is exactly 368,640 bytes
- Verify frames arrive at approximately 60fps rate
- Verify BGRA format (check known pixel values)

#### FRAME_DELTA (0x61)
Delta-encoded video frame (only changed pixels).

| Direction | Payload              |
|-----------|----------------------|
| Broadcast | Delta-encoded data   |

**Payload Format**:
```
Offset 0-3: Number of changed pixels (4 bytes, big-endian)
For each changed pixel:
  Offset N+0-2: Pixel index (3 bytes, big-endian)
  Offset N+3-6: BGRA color (4 bytes)
```

**Note**: Reserved for future web client optimization.

#### FRAME_CONFIG (0x62)
Video configuration message.

| Direction | Payload           |
|-----------|-------------------|
| Response  | Configuration data |

**Payload Format**:
```
Offset 0-1: Width (2 bytes, big-endian)
Offset 2-3: Height (2 bytes, big-endian)
Offset 4: Bytes per pixel (1 byte)
Offset 5: Frame rate (1 byte, approximate fps)
```

#### VIDEO_SUBSCRIBE (0x63)
Request video stream subscription.

| Direction | Payload |
|-----------|---------|
| Request   | 1 byte  |

**Payload Format**:
```
Offset 0: Format preference
  0x00 = Raw BGRA (FRAME_RAW)
  0x01 = Delta encoded (FRAME_DELTA)
```

**Test Case**: Send VIDEO_SUBSCRIBE(0x00), verify FRAME_RAW messages start arriving.

#### VIDEO_UNSUBSCRIBE (0x64)
Cancel video stream subscription.

| Direction | Payload |
|-----------|---------|
| Request   | Empty   |

**Test Case**: Subscribe, unsubscribe, verify no more FRAME_RAW messages.

### Audio Messages (0x80-0x9F)

#### AUDIO_PCM (0x80)
Raw audio PCM samples (server → client).

| Direction | Payload              |
|-----------|----------------------|
| Broadcast | 16-bit PCM samples   |

**Payload Format**:
```
N × 2 bytes of 16-bit signed PCM samples
Format: Mono, 44.1kHz, little-endian (native)
Typical size: ~735 samples × 2 = ~1470 bytes per frame
```

**Audio Constants**:
- Sample rate: 44,100 Hz
- Bits per sample: 16
- Channels: 1 (mono)
- Samples per frame: ~735 (44100 / 60)

**Test Cases**:
- Subscribe to audio, verify samples arrive at 60fps rate
- Verify sample count is approximately 735 per frame
- Verify samples are valid signed 16-bit values

#### AUDIO_CONFIG (0x81)
Audio configuration message.

| Direction | Payload           |
|-----------|-------------------|
| Response  | Configuration data |

**Payload Format**:
```
Offset 0-3: Sample rate (4 bytes, big-endian)
Offset 4: Bits per sample (1 byte)
Offset 5: Channels (1 byte)
```

#### AUDIO_SYNC (0x82)
Audio synchronization timestamp.

| Direction | Payload                           |
|-----------|-----------------------------------|
| Broadcast | 8 bytes frame number (big-endian) |

**Payload Format**:
```
Offset 0-7: Frame number (UInt64, big-endian)
```

**Test Case**: Parse frame number, verify it increments over time.

#### AUDIO_SUBSCRIBE (0x83)
Request audio stream subscription.

| Direction | Payload |
|-----------|---------|
| Request   | Empty   |

**Test Case**: Send AUDIO_SUBSCRIBE, verify AUDIO_PCM messages start arriving.

#### AUDIO_UNSUBSCRIBE (0x84)
Cancel audio stream subscription.

| Direction | Payload |
|-----------|---------|
| Request   | Empty   |

**Test Case**: Subscribe, unsubscribe, verify no more AUDIO_PCM messages.

## AESP Error Handling

### Invalid Messages

The server should respond with ERROR (0x3F) for:
- Invalid magic number
- Unsupported protocol version
- Unknown message type
- Invalid payload size
- Malformed payload data

### Connection Errors

- Server not reachable: Connection refused on all ports
- Server overloaded: Slow response times, dropped frames
- Client disconnected: Server removes from subscriber lists

### Test Cases for Error Handling

1. **Invalid Magic**: Send message with magic 0x0000, verify ERROR response
2. **Invalid Version**: Send message with version 0xFF, verify ERROR response
3. **Unknown Type**: Send message with type 0xFE, verify ERROR response
4. **Oversized Payload**: Send message with length > 16MB, verify ERROR response
5. **Truncated Message**: Send header only, verify server waits for more data
6. **Empty Payload**: Send RESET with empty payload, verify ERROR response

## AESP Example Sessions

### Basic Connection Test
```
Client → Server: [0xAE, 0x50, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00]  // PING
Server → Client: [0xAE, 0x50, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00]  // PONG
```

### Video Subscription
```
Client → Server (Control): [0xAE, 0x50, 0x01, 0x63, 0x00, 0x00, 0x00, 0x01, 0x00]
                           // VIDEO_SUBSCRIBE, raw format

Server → Client (Video): [0xAE, 0x50, 0x01, 0x60, 0x00, 0x05, 0xA0, 0x00, <368640 bytes>]
                         // FRAME_RAW (sent repeatedly at 60fps)
```

---

# Part 2: CLI/GUI Socket Protocol

The CLI protocol is a text-based protocol for REPL communication between the `attic` CLI tool and the GUI application. It is designed for Emacs comint mode compatibility.

## Connection

### Socket Location

The GUI creates a socket at startup:
```
/tmp/attic-<pid>.sock
```

Where `<pid>` is the GUI process ID.

### Discovery

The CLI looks for existing sockets:
```bash
ls /tmp/attic-*.sock
```

If multiple sockets exist (unlikely), use the most recent by modification time.

### Handshake

```
CLI: CMD:ping
GUI: OK:pong
```

If no response within 1 second, retry up to 3 times before failing.

**Test Case**: Connect to socket, send `CMD:ping\n`, verify `OK:pong\n` received.

## Message Format

### Request (CLI → GUI)

```
CMD:<command> [arguments...]
```

- Single line, terminated by newline (`\n`)
- Command and arguments separated by spaces
- Arguments containing spaces must be quoted or escaped
- Maximum line length: 4096 bytes

**Test Cases**:
- Empty command: `CMD:\n` → `ERR:Invalid command ''`
- Long command: `CMD:` + 4096 'x' characters → `ERR:Line too long`

### Response (GUI → CLI)

**Success:**
```
OK:<response-data>
```

**Error:**
```
ERR:<error-message>
```

**Multi-line Response:**

Lines are joined with record separator (`\x1E`):
```
OK:line1\x1Eline2\x1Eline3
```

The CLI splits on `\x1E` for display.

**Test Case**: Request disassembly, verify multi-line response uses `\x1E` separator.

### Async Events (GUI → CLI)

Events can arrive at any time:
```
EVENT:<event-type> <data>
```

The CLI must handle these between commands.

**Test Case**: Set breakpoint, resume, verify `EVENT:breakpoint` received when hit.

## Commands Reference

### Emulator Control

#### ping
Test connection.
```
CMD:ping
OK:pong
```

**Test Case**: Basic connectivity test.

#### pause
Pause emulator execution.
```
CMD:pause
OK:paused
```

**Test Case**: Verify emulation stops.

#### resume
Resume emulator execution.
```
CMD:resume
OK:resumed
```

**Test Case**: After pause, verify emulation resumes.

#### step
Execute one or more instructions.
```
CMD:step
OK:stepped A=$00 X=$00 Y=$00 S=$FF P=$34 PC=$E477

CMD:step 10
OK:stepped A=$4F X=$03 Y=$00 S=$FD P=$30 PC=$E4A2
```

**Test Cases**:
- `CMD:step\n` - single step, verify PC changes
- `CMD:step 100\n` - multiple steps, verify PC advanced
- `CMD:step -1\n` - invalid count → `ERR:Invalid step count`

#### stepover
Step over JSR subroutine calls (treats JSR as atomic). Alias: `so`.
```
CMD:stepover
OK:stepped A=$00 X=$00 Y=$00 S=$FF P=$34 PC=$E47B

CMD:so
OK:stepped A=$4F X=$03 Y=$00 S=$FD P=$30 PC=$E4A2
```

**Test Case**: Step over a JSR instruction, verify PC is at instruction after JSR.

#### until
Run emulator until PC reaches a specific address.
```
CMD:until $E480
OK:stopped at $E480
```

**Test Cases**:
- `CMD:until $0600\n` - run until address reached
- `CMD:until xyz\n` → `ERR:Invalid address 'xyz'`

#### boot
Load and boot a file into the emulator.
```
CMD:boot /path/to/game.atr
OK:booted /path/to/game.atr
```

**Supported file types**: ATR, XFD, ATX, DCM, PRO, XEX, COM, EXE, BAS, LST, CART, ROM, CAS.

**Test Cases**:
- `CMD:boot /valid/path.atr\n` - boot valid file
- `CMD:boot /nonexistent.atr\n` → `ERR:File not found`

#### version
Query protocol version.
```
CMD:version
OK:version 1.0
```

#### reset
Reset the emulator.
```
CMD:reset cold
OK:reset cold

CMD:reset warm
OK:reset warm
```

**Test Cases**:
- Cold reset: Verify boot sequence starts
- Warm reset: Verify softer reset
- `CMD:reset invalid\n` → `ERR:Invalid reset type`

#### status
Get emulator status.
```
CMD:status
OK:status running PC=$E477 D1=/path/to/disk.atr D2=(none) BP=$600A,$602F
```

Status fields:
- `running` or `paused` - emulator state
- `PC=$XXXX` - current program counter
- `D1=...` through `D8=...` - mounted disk paths or `(none)`
- `BP=...` - comma-separated breakpoint addresses or `(none)`

**Test Case**: Verify all fields present and parseable.

### Memory Operations

#### read
Read bytes from memory.
```
CMD:read $0600 16
OK:data A9,00,8D,00,D4,A9,01,8D,01,D4,60,00,00,00,00,00
```

Address can be hex ($xxxx) or decimal. Length is in bytes.

**Test Cases**:
- `CMD:read $0600 16\n` - hex address, verify 16 comma-separated bytes
- `CMD:read 1536 16\n` - decimal address (1536 = $0600)
- `CMD:read $FFFF 2\n` - read crosses boundary → verify handles correctly
- `CMD:read $GGGG 1\n` → `ERR:Invalid address 'GGGG'`
- `CMD:read $0600\n` → `ERR:Missing count`

#### write
Write bytes to memory.
```
CMD:write $0600 A9,00,8D,00,D4
OK:written 5
```

Bytes are comma-separated hex values.

**Test Cases**:
- Write and read back: Write A9,00, read $0600, verify A9,00
- `CMD:write $0600 GG\n` → `ERR:Invalid byte value 'GG'`
- `CMD:write $0600\n` → `ERR:Missing data`

#### fill
Fill a memory range with a single byte value.
```
CMD:fill $0600 $06FF $00
OK:filled 256 bytes
```

Address and value can be hex ($xxxx) or decimal.

**Test Cases**:
- `CMD:fill $0600 $06FF $EA\n` - fill range with NOP
- `CMD:fill $0600\n` → `ERR:Missing end address`

#### screen
Read the text displayed on the GRAPHICS 0 screen as a 40×24 character string.
```
CMD:screen
OK:<40x24 character text, lines joined with \x1E>
```

Only works when the emulator is in GRAPHICS 0 (text) mode.

### CPU State

#### registers
Get or set CPU registers.
```
CMD:registers
OK:A=$00 X=$00 Y=$00 S=$FF P=$34 PC=$E477

CMD:registers A=$50 X=$10
OK:A=$50 X=$10 Y=$00 S=$FF P=$34 PC=$E477
```

Register names: A, X, Y, S (stack pointer), P (status), PC

**Test Cases**:
- Get all registers
- Set A register, read back, verify
- `CMD:registers Q=$FF\n` → `ERR:Invalid register 'Q'`
- `CMD:registers A=$GG\n` → `ERR:Invalid value 'GG'`

### Disassembly

#### disassemble
Disassemble memory at an address. Alias: `d`.
```
CMD:disassemble $0600 8
OK:$0600  A9 00     LDA #$00
$0602  8D 00 D4  STA DMACTL
$0605  A9 01     LDA #$01
$0607  8D 01 D4  STA $D401
$060A  60        RTS
$060B  EA        NOP
$060C  EA        NOP
$060D  EA        NOP
```

Default (no arguments) disassembles 16 lines starting from current PC:
```
CMD:d
OK:$E477  A9 00     LDA #$00
...
```

With just address, disassembles 16 lines from that address:
```
CMD:d $0600
OK:$0600  A9 00     LDA #$00
...
```

**Features**:
- Address can be hex ($xxxx, 0xXXXX) or decimal
- Output includes symbolic labels for known addresses (hardware registers, OS vectors)
- Branch instructions show relative offset: `BNE $0607 (+5)`
- Illegal opcodes are marked
- Multi-line response uses record separator (`\x1E`)

**Test Cases**:
- `CMD:d\n` - disassemble from PC, default 16 lines
- `CMD:d $0600\n` - disassemble from $0600, 16 lines
- `CMD:d $0600 8\n` - disassemble 8 lines from $0600
- `CMD:d 1536 8\n` - decimal address
- `CMD:d xyz\n` → `ERR:Invalid address 'xyz'`
- `CMD:d $0600 0\n` → `ERR:Invalid line count '0'`

### Assembly

The assembler supports single-line and interactive (multi-line) modes. All
instructions use standard 6502 mnemonics with MAC65-style syntax.

#### assemble (single-line)
Assemble one instruction at a specific address.
```
CMD:assemble $0600 LDA #$00
OK:$0600: A9 00     LDA #$00
```

Alias: `asm`, `a`.

**Test Cases**:
- `CMD:a $0600 NOP\n` - assemble NOP, verify byte EA at $0600
- `CMD:a $0600 INVALID\n` → `ERR:Assembly error: ...`

#### assemble (start interactive session)
Start an interactive assembly session at the given address. Subsequent
instructions are fed with `assemble input` and the address advances
automatically.
```
CMD:assemble $0600
OK:ASM $0600
```

**Test Case**: Start session, verify `ASM $0600` response.

#### assemble input
Feed an instruction to the active interactive assembly session. The
server assembles the instruction at the current address, writes the
bytes to memory, and returns the formatted line plus the next address
(separated by the record separator `\x1E`).
```
CMD:asm input LDA #$00
OK:$0600: A9 00     LDA #$00\x1E$0602

CMD:asm input STA $D400
OK:$0602: 8D 00 D4  STA $D400\x1E$0605
```

If no session is active:
```
CMD:asm input NOP
ERR:No active assembly session. Start one with: assemble $<address>
```

An invalid instruction returns an error but keeps the session alive so
the caller can retry:
```
CMD:asm input INVALID
ERR:Assembly error: Unknown mnemonic 'INVALID'
```

#### assemble end
End the active interactive assembly session and return a summary.
```
CMD:asm end
OK:Assembly complete: 5 bytes at $0600-$0604
```

If no session is active:
```
CMD:asm end
ERR:No active assembly session
```

#### Complete interactive session example
```
CMD:assemble $0600
OK:ASM $0600

CMD:asm input LDA #$00
OK:$0600: A9 00     LDA #$00\x1E$0602

CMD:asm input STA $D400
OK:$0602: 8D 00 D4  STA $D400\x1E$0605

CMD:asm input RTS
OK:$0605: 60        RTS\x1E$0606

CMD:asm end
OK:Assembly complete: 6 bytes at $0600-$0605
```

### Breakpoints

#### breakpoint set
Set a breakpoint.
```
CMD:breakpoint set $600A
OK:breakpoint set $600A
```

**Test Cases**:
- Set breakpoint, verify in list
- `CMD:breakpoint set $600A\n` twice → `ERR:Breakpoint already set at $600A`

#### breakpoint clear
Clear a breakpoint.
```
CMD:breakpoint clear $600A
OK:breakpoint cleared $600A
```

**Test Cases**:
- Clear existing breakpoint
- `CMD:breakpoint clear $600A\n` when not set → `ERR:No breakpoint at $600A`

#### breakpoint clearall
Clear all breakpoints.
```
CMD:breakpoint clearall
OK:breakpoints cleared
```

#### breakpoint list
List all breakpoints.
```
CMD:breakpoint list
OK:breakpoints $600A,$602F,$E477
```

Empty list:
```
CMD:breakpoint list
OK:breakpoints (none)
```

**Test Case**: Set 3 breakpoints, list, verify all 3 present.

### Disk Operations

#### mount
Mount a disk image.
```
CMD:mount 1 /Users/nick/disks/game.atr
OK:mounted 1 /Users/nick/disks/game.atr
```

**Test Cases**:
- Mount valid ATR
- `CMD:mount 1 /nonexistent.atr\n` → `ERR:File not found '/nonexistent.atr'`
- `CMD:mount 9 /file.atr\n` → `ERR:Invalid drive number`

#### unmount
Unmount a disk.
```
CMD:unmount 1
OK:unmounted 1
```

**Test Case**: Unmount drive not mounted → `ERR:Disk image not mounted: 1`

#### drives
List mounted drives.
```
CMD:drives
OK:drives 1=/Users/nick/disks/game.atr,2=/Users/nick/disks/save.atr

CMD:drives
OK:drives (none)
```

### State Management

#### state save
Save emulator state.
```
CMD:state save /Users/nick/saves/game.attic
OK:state saved /Users/nick/saves/game.attic
```

**Test Cases**:
- Save to valid path
- `CMD:state save /readonly/path.attic\n` → `ERR:Permission denied '/readonly/path.attic'`

#### state load
Load emulator state.
```
CMD:state load /Users/nick/saves/game.attic
OK:state loaded /Users/nick/saves/game.attic
```

**Test Cases**:
- Load valid state
- `CMD:state load /nonexistent.attic\n` → `ERR:File not found '/nonexistent.attic'`
- Load corrupted state → `ERR:State file corrupt`

### Display

#### screenshot
Capture screen to file.
```
CMD:screenshot /Users/nick/screenshots/screen.png
OK:screenshot /Users/nick/screenshots/screen.png
```

Default path if not specified:
```
CMD:screenshot
OK:screenshot /Users/nick/Desktop/Attic-<YYYYMMDD-HHMMSS>.png
```

### BASIC Injection

#### inject basic
Inject tokenized BASIC program into memory.
```
CMD:inject basic <base64-encoded-tokenized-data>
OK:injected basic 1234 bytes
```

The data is base64-encoded binary of the tokenized BASIC program including all memory structures (VNTP, VVTP, STMTAB, etc.).

**Test Cases**:
- Inject valid BASIC program
- `CMD:inject basic !!!invalid!!!\n` → `ERR:Invalid base64 data`

### Keyboard Injection

#### inject keys
Inject keystrokes as if typed.
```
CMD:inject keys RUN\n
OK:injected keys 4
```

Escape sequences:
- `\n` - Return
- `\t` - Tab
- `\e` - Escape
- `\\` - Backslash

**Test Case**: Inject "PRINT 123\n", verify output appears on emulated screen.

### BASIC Subsystem

Commands for managing BASIC programs. All prefixed with `basic`.

#### basic (line entry)
Enter or replace a BASIC line (tokenized and injected into emulator memory).
```
CMD:basic 10 PRINT "HELLO"
OK:injected
```

#### basic new
Clear BASIC program from memory.
```
CMD:basic new
OK:cleared
```

#### basic run
Execute the BASIC program.
```
CMD:basic run
OK:running
```

#### basic list
List the BASIC program. Optional `atascii` flag enables rich ATASCII rendering.
```
CMD:basic list
OK:10 PRINT "HELLO"\x1E20 GOTO 10

CMD:basic list atascii
OK:10 PRINT "HELLO"\x1E20 GOTO 10
```

#### basic del
Delete BASIC line(s) by number or range.
```
CMD:basic del 10
OK:deleted 1 lines

CMD:basic del 10-50
OK:deleted 5 lines
```

#### basic stop
Stop a running BASIC program (equivalent to BREAK key).
```
CMD:basic stop
OK:stopped
```

#### basic cont
Continue a stopped BASIC program.
```
CMD:basic cont
OK:running
```

#### basic vars
Show all BASIC variables and their values.
```
CMD:basic vars
OK:I=10\x1ECOUNT=42\x1ENAME$="CLAUDE"
```

#### basic var
Show a specific BASIC variable.
```
CMD:basic var X
OK:X=100 (integer)
```

#### basic info
Show BASIC program metadata.
```
CMD:basic info
OK:program size=1234 lines=42 ...
```

#### basic renum
Renumber BASIC lines. Optional start and step arguments (defaults: 10, 10).
```
CMD:basic renum
OK:renumbered to 10,20,30,...

CMD:basic renum 100 20
OK:renumbered to 100,120,140,...
```

#### basic save
Save tokenized BASIC to ATR disk. Supports optional `D#:` drive prefix.
```
CMD:basic save D:MYPROG
OK:saved to D1:MYPROG

CMD:basic save D2:BACKUP
OK:saved to D2:BACKUP
```

#### basic load
Load tokenized BASIC from ATR disk. Supports optional `D#:` drive prefix.
```
CMD:basic load D:MYPROG
OK:loaded from D1:MYPROG
```

#### basic export
Export BASIC program to host filesystem as text.
```
CMD:basic export ~/game.bas
OK:exported to /Users/nick/game.bas
```

#### basic import
Import BASIC program from host filesystem text file.
```
CMD:basic import ~/game.bas
OK:imported from /Users/nick/game.bas
```

#### basic dir
List files on ATR disk. Optional drive number (default: current drive).
```
CMD:basic dir
OK:<directory listing>

CMD:basic dir 2
OK:<D2: directory listing>
```

### DOS File System

Commands for managing ATR disk images and files. All prefixed with `dos`.

#### dos cd
Change current working drive.
```
CMD:dos cd 2
OK:changed to D2:
```

#### dos dir
List files on current drive. Optional wildcard pattern.
```
CMD:dos dir
OK:<directory listing>

CMD:dos dir *.BAS
OK:<filtered listing>
```

#### dos info
Show detailed file information.
```
CMD:dos info GAME.BAS
OK:GAME.BAS 2048 bytes 8 sectors locked=0
```

#### dos type
Display text file contents (ATASCII decoded).
```
CMD:dos type README.TXT
OK:Welcome to my disk!\x1EHave fun!
```

#### dos dump
Hex dump of file contents.
```
CMD:dos dump PROG.COM
OK:<hex dump output>
```

#### dos copy
Copy file between drives. Supports `D#:` prefix on source and destination.
```
CMD:dos copy D1:SRC.BAS D2:DST.BAS
OK:copied D1:SRC.BAS to D2:DST.BAS
```

#### dos rename
Rename file on current drive.
```
CMD:dos rename OLDNAME.BAS NEWNAME.BAS
OK:renamed to NEWNAME.BAS
```

#### dos delete
Delete file from current drive.
```
CMD:dos delete TEMP.BAS
OK:deleted TEMP.BAS
```

#### dos lock
Set read-only flag on file.
```
CMD:dos lock READONLY.BAS
OK:locked READONLY.BAS
```

#### dos unlock
Clear read-only flag on file.
```
CMD:dos unlock READONLY.BAS
OK:unlocked READONLY.BAS
```

#### dos export
Export ATR file to host filesystem.
```
CMD:dos export GAME.BAS ~/game.bas
OK:exported to ~/game.bas
```

#### dos import
Import host file to ATR disk.
```
CMD:dos import ~/game.bas GAME.BAS
OK:imported from ~/game.bas
```

#### dos newdisk
Create a new blank ATR disk image. Types: `sd` (90K), `ed` (130K), `dd` (180K).
```
CMD:dos newdisk ~/disk.atr
OK:created disk.atr (sd)

CMD:dos newdisk ~/disk.atr ed
OK:created disk.atr (ed)
```

#### dos format
Format current drive (erases all data).
```
CMD:dos format
OK:formatted current disk
```

### Session Control

#### quit
Disconnect CLI (leave GUI running).
```
CMD:quit
OK:goodbye
[connection closed by CLI]
```

#### shutdown
Terminate GUI and disconnect.
```
CMD:shutdown
OK:shutting down
[connection closed by GUI]
```

## Async Events

Events are sent by the GUI without a corresponding command.

### breakpoint
Breakpoint was hit.
```
EVENT:breakpoint $600A A=$4F X=$00 Y=$03 S=$F7 P=$B4
```

**Test Case**: Set breakpoint, resume, verify event received when hit.

### stopped
Emulator stopped (e.g., BRK instruction without breakpoint).
```
EVENT:stopped $600A
```

### error
Async error occurred.
```
EVENT:error Disk read error on D1:
```

## Error Responses

All errors follow the format:
```
ERR:<error-message>
```

### Common Errors

```
ERR:Invalid command 'foo'
ERR:Invalid address 'ZZZZ'
ERR:Invalid register 'Q'
ERR:File not found '/path/to/file'
ERR:Permission denied '/path/to/file'
ERR:Disk image not mounted: 1
ERR:Breakpoint already set at $600A
ERR:No breakpoint at $600A
ERR:Invalid base64 data
ERR:State file corrupt
```

## Protocol Versioning

Future versions may add a version negotiation:
```
CMD:version
OK:version 1.0

CMD:version 2.0
ERR:Unsupported version 2.0, server is 1.0
```

For now, version 1.0 is implied.

## CLI Protocol Implementation Notes

### Socket Permissions

The socket should be created with mode 0600 (user read/write only) for security.

### Buffer Management

- Read buffer: 8192 bytes
- Write buffer: 8192 bytes
- Line accumulator for partial reads

### Timeout Handling

- Command timeout: 30 seconds (for long operations like state save)
- Ping timeout: 1 second
- Connection timeout: 5 seconds

### Thread Safety

The GUI should handle socket I/O on a dedicated thread, queuing commands to the main thread for execution. Responses are sent back on the socket thread.

```swift
class SocketHandler {
    let socket: FileHandle
    let commandQueue: DispatchQueue
    let responseQueue: DispatchQueue

    func handleCommand(_ line: String) {
        commandQueue.async {
            let response = self.execute(line)
            self.responseQueue.async {
                self.send(response)
            }
        }
    }
}
```

---

# Part 3: Test Coverage Matrix

## AESP Protocol Test Coverage

| Category | Message Type | Encode | Decode | Round-trip | Error Cases |
|----------|--------------|--------|--------|------------|-------------|
| Control  | PING         | ✓      | ✓      | ✓          | -           |
| Control  | PONG         | ✓      | ✓      | ✓          | -           |
| Control  | PAUSE        | ✓      | ✓      | ✓          | -           |
| Control  | RESUME       | ✓      | ✓      | ✓          | -           |
| Control  | RESET        | ✓      | ✓      | ✓          | Invalid type |
| Control  | STATUS       | ✓      | ✓      | ✓          | -           |
| Control  | INFO         | ✓      | ✓      | ✓          | -           |
| Control  | BOOT_FILE    | ✓      | ✓      | ✓          | File not found |
| Control  | ACK          | ✓      | ✓      | ✓          | -           |
| Control  | ERROR        | ✓      | ✓      | ✓          | -           |
| Input    | KEY_DOWN     | ✓      | ✓      | ✓          | Invalid format |
| Input    | KEY_UP       | ✓      | ✓      | ✓          | -           |
| Input    | JOYSTICK     | ✓      | ✓      | ✓          | Invalid port |
| Input    | CONSOLE_KEYS | ✓      | ✓      | ✓          | -           |
| Input    | PADDLE       | ✓      | ✓      | ✓          | Invalid paddle |
| Video    | FRAME_RAW    | ✓      | ✓      | ✓          | Wrong size  |
| Video    | FRAME_DELTA  | ✓      | ✓      | ✓          | Invalid format |
| Video    | FRAME_CONFIG | ✓      | ✓      | ✓          | -           |
| Video    | VIDEO_SUBSCRIBE | ✓   | ✓      | ✓          | -           |
| Video    | VIDEO_UNSUBSCRIBE | ✓ | ✓      | ✓          | -           |
| Audio    | AUDIO_PCM    | ✓      | ✓      | ✓          | -           |
| Audio    | AUDIO_CONFIG | ✓      | ✓      | ✓          | -           |
| Audio    | AUDIO_SYNC   | ✓      | ✓      | ✓          | Invalid format |
| Audio    | AUDIO_SUBSCRIBE | ✓   | ✓      | ✓          | -           |
| Audio    | AUDIO_UNSUBSCRIBE | ✓ | ✓      | ✓          | -           |

## Header Validation Tests

| Test | Input | Expected |
|------|-------|----------|
| Valid header | Magic=0xAE50, Version=0x01 | Success |
| Invalid magic | Magic=0x0000 | AESPError.invalidMagic |
| Invalid magic high byte | Magic=0xFF50 | AESPError.invalidMagic |
| Invalid magic low byte | Magic=0xAEFF | AESPError.invalidMagic |
| Invalid version 0 | Version=0x00 | AESPError.unsupportedVersion |
| Invalid version 2 | Version=0x02 | AESPError.unsupportedVersion |
| Unknown message type | Type=0xFE | AESPError.unknownMessageType |
| Payload too large | Length=0x02000000 | AESPError.payloadTooLarge |
| Truncated header | 4 bytes only | AESPError.insufficientData |
| Truncated payload | Header + partial payload | AESPError.insufficientData |

## CLI Protocol Test Coverage

| Command | Success | Error Cases |
|---------|---------|-------------|
| ping | ✓ | - |
| pause | ✓ | - |
| resume | ✓ | - |
| step | ✓ | Invalid count, Negative count |
| stepover | ✓ | - |
| until | ✓ | Invalid address |
| boot | ✓ | File not found |
| version | ✓ | - |
| reset | ✓ | Invalid type |
| status | ✓ | - |
| disassemble | ✓ | Invalid address, Invalid line count |
| assemble (single) | ✓ | Invalid instruction |
| assemble (session) | ✓ | - |
| assemble input | ✓ | No session, Invalid instruction |
| assemble end | ✓ | No session |
| read | ✓ | Invalid address, Missing count |
| write | ✓ | Invalid address, Invalid byte, Missing data |
| fill | ✓ | Missing address, Invalid value |
| screen | ✓ | - |
| registers (get) | ✓ | - |
| registers (set) | ✓ | Invalid register, Invalid value |
| breakpoint set | ✓ | Already set |
| breakpoint clear | ✓ | Not found |
| breakpoint clearall | ✓ | - |
| breakpoint list | ✓ | - |
| mount | ✓ | File not found, Invalid drive |
| unmount | ✓ | Not mounted |
| drives | ✓ | - |
| state save | ✓ | Permission denied |
| state load | ✓ | File not found, Corrupt file |
| screenshot | ✓ | Permission denied |
| inject basic | ✓ | Invalid base64 |
| inject keys | ✓ | - |
| basic (line entry) | ✓ | Syntax error |
| basic new | ✓ | - |
| basic run | ✓ | - |
| basic list | ✓ | - |
| basic del | ✓ | Invalid line, Invalid range |
| basic stop | ✓ | - |
| basic cont | ✓ | - |
| basic vars | ✓ | - |
| basic var | ✓ | Variable not found |
| basic info | ✓ | - |
| basic renum | ✓ | Invalid start/step |
| basic save | ✓ | No disk, File error |
| basic load | ✓ | File not found |
| basic export | ✓ | Permission denied |
| basic import | ✓ | File not found |
| basic dir | ✓ | No disk mounted |
| dos cd | ✓ | Invalid drive |
| dos dir | ✓ | No disk mounted |
| dos info | ✓ | File not found |
| dos type | ✓ | File not found |
| dos dump | ✓ | File not found |
| dos copy | ✓ | File not found, Dest drive not mounted |
| dos rename | ✓ | File not found |
| dos delete | ✓ | File not found, File locked |
| dos lock | ✓ | File not found |
| dos unlock | ✓ | File not found |
| dos export | ✓ | File not found, Permission denied |
| dos import | ✓ | File not found, Disk full |
| dos newdisk | ✓ | Permission denied, Invalid type |
| dos format | ✓ | No disk mounted |
| quit | ✓ | - |
| shutdown | ✓ | - |
