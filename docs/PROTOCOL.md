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
| 47800 | Control   | Low        | Commands, status, memory access      |
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
| 0x00-0x3F | Control  | Commands, status, memory access       |
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

#### MEMORY_READ (0x10)
Read memory from emulator.

| Direction | Payload                          |
|-----------|----------------------------------|
| Request   | 4 bytes (address + count)        |
| Response  | MEMORY_READ with requested bytes |

**Request Payload Format**:
```
Offset 0-1: Address (2 bytes, big-endian)
Offset 2-3: Count (2 bytes, big-endian, max 65535)
```

**Response Payload Format**:
```
Offset 0-N: Requested memory bytes
```

**Test Cases**:
- Read single byte: MEMORY_READ($0600, 1), verify 1 byte returned
- Read block: MEMORY_READ($0000, 256), verify 256 bytes returned
- Read high memory: MEMORY_READ($E000, 16), verify ROM bytes returned
- Maximum read: MEMORY_READ($0000, 65535), verify 65535 bytes returned

#### MEMORY_WRITE (0x11)
Write memory to emulator.

| Direction | Payload                    |
|-----------|----------------------------|
| Request   | 2 bytes address + N bytes data |
| Response  | ACK(0x11)                  |

**Request Payload Format**:
```
Offset 0-1: Address (2 bytes, big-endian)
Offset 2-N: Data bytes to write
```

**Test Cases**:
- Write single byte: MEMORY_WRITE($0600, [0xA9]), read back to verify
- Write block: MEMORY_WRITE($0600, [0xA9, 0x00, 0x60]), read back to verify
- Write to page zero: MEMORY_WRITE($00, [0xFF]), read back to verify

#### REGISTERS_READ (0x12)
Read CPU registers.

| Direction | Payload                  |
|-----------|--------------------------|
| Request   | Empty                    |
| Response  | REGISTERS_READ (8 bytes) |

**Response Payload Format**:
```
Offset 0: A register (1 byte)
Offset 1: X register (1 byte)
Offset 2: Y register (1 byte)
Offset 3: S register (stack pointer, 1 byte)
Offset 4: P register (processor status, 1 byte)
Offset 5-6: PC register (program counter, 2 bytes big-endian)
Offset 7: Reserved (1 byte, always 0x00)
```

**Test Case**: Send REGISTERS_READ, verify 8-byte response with valid values.

#### REGISTERS_WRITE (0x13)
Write CPU registers.

| Direction | Payload      |
|-----------|--------------|
| Request   | 8 bytes (same format as REGISTERS_READ response) |
| Response  | ACK(0x13)    |

**Test Case**: Write A=$50, read back, verify A=$50.

#### BREAKPOINT_SET (0x20)
Set a breakpoint.

| Direction | Payload                        |
|-----------|--------------------------------|
| Request   | 2 bytes address (big-endian)   |
| Response  | ACK(0x20)                      |

**Test Case**: Set breakpoint at $0600, run code to $0600, verify BREAKPOINT_HIT received.

#### BREAKPOINT_CLEAR (0x21)
Clear a breakpoint.

| Direction | Payload                        |
|-----------|--------------------------------|
| Request   | 2 bytes address (big-endian)   |
| Response  | ACK(0x21)                      |

**Test Case**: Set breakpoint, clear it, verify execution continues past that address.

#### BREAKPOINT_LIST (0x22)
List all breakpoints.

| Direction | Payload                        |
|-----------|--------------------------------|
| Request   | Empty                          |
| Response  | Array of 2-byte addresses      |

**Response Payload Format**:
```
Offset 0-1: First breakpoint address (big-endian)
Offset 2-3: Second breakpoint address (big-endian)
...
```

**Test Case**: Set 3 breakpoints, list, verify 6 bytes returned (3 × 2).

#### BREAKPOINT_HIT (0x23)
Notification that a breakpoint was hit (server → client).

| Direction | Payload                        |
|-----------|--------------------------------|
| Notification | 2 bytes address (big-endian) |

**Test Case**: Set breakpoint, run to it, verify BREAKPOINT_HIT received with correct address.

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
6. **Invalid Address**: MEMORY_READ from $FFFF+1, verify ERROR response

## AESP Example Sessions

### Basic Connection Test
```
Client → Server: [0xAE, 0x50, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00]  // PING
Server → Client: [0xAE, 0x50, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00]  // PONG
```

### Memory Read
```
Client → Server: [0xAE, 0x50, 0x01, 0x10, 0x00, 0x00, 0x00, 0x04, 0x06, 0x00, 0x00, 0x10]
                 // MEMORY_READ, address=$0600, count=16

Server → Client: [0xAE, 0x50, 0x01, 0x10, 0x00, 0x00, 0x00, 0x10, <16 bytes of memory>]
                 // MEMORY_READ response with 16 bytes
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
| Control  | ACK          | ✓      | ✓      | ✓          | -           |
| Control  | MEMORY_READ  | ✓      | ✓      | ✓          | Invalid addr, Invalid count |
| Control  | MEMORY_WRITE | ✓      | ✓      | ✓          | Invalid addr |
| Control  | REGISTERS_READ | ✓    | ✓      | ✓          | -           |
| Control  | REGISTERS_WRITE | ✓   | ✓      | ✓          | Invalid format |
| Control  | BREAKPOINT_SET | ✓    | ✓      | ✓          | Duplicate   |
| Control  | BREAKPOINT_CLEAR | ✓  | ✓      | ✓          | Not found   |
| Control  | BREAKPOINT_LIST | ✓   | ✓      | ✓          | -           |
| Control  | BREAKPOINT_HIT | ✓    | ✓      | ✓          | -           |
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
| reset | ✓ | Invalid type |
| status | ✓ | - |
| disassemble | ✓ | Invalid address, Invalid line count |
| read | ✓ | Invalid address, Missing count |
| write | ✓ | Invalid address, Invalid byte, Missing data |
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
| quit | ✓ | - |
| shutdown | ✓ | - |
