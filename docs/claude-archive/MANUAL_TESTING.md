# Manual Testing Checklist

This document provides a comprehensive checklist for manually testing the Attic Emulator. These tests cover functionality that cannot be easily automated or requires visual/audio verification.

## Prerequisites

Before testing, ensure you have:
- macOS 15+ (Sequoia)
- ROMs: `ATARIXL.ROM` and `ATARIBAS.ROM` in one of:
  - `~/.attic/ROM/`
  - `~/Library/Application Support/Attic/ROM/`
  - Current directory
- At least one ATR disk image for disk testing
- Built the project: `swift build`

---

## 1. AtticServer Tests

### 1.1 Server Startup
- [ ] `swift run AtticServer` starts without errors
- [ ] Server displays "Listening on control port 47800"
- [ ] Server displays "Listening on video port 47801"
- [ ] Server displays "Listening on audio port 47802"
- [ ] Server creates CLI socket at `/tmp/attic-<pid>.sock`
- [ ] ROM discovery works from default paths

### 1.2 Server with Custom ROM Path
- [ ] `swift run AtticServer --rom-path ~/custom/ROMs` works
- [ ] Error message if ROMs not found at specified path

### 1.3 Server Shutdown
- [ ] Ctrl+C gracefully shuts down server
- [ ] Socket file is removed on shutdown
- [ ] All client connections are closed

---

## 2. AtticGUI Tests

### 2.1 Client Mode (Default)

#### Connection
- [ ] GUI displays error when server not running
- [ ] Start AtticServer, then GUI connects successfully
- [ ] "READY" prompt appears on Atari screen

#### Video
- [ ] Display is 384x240 pixels (or scaled)
- [ ] No visible tearing during animation
- [ ] Frame rate maintains ~60fps
- [ ] Colors match NTSC Atari palette

#### Audio
- [ ] Boot sound plays
- [ ] Keyclick sound when typing
- [ ] No audio crackling or pops
- [ ] Audio syncs with video (no drift)

### 2.2 Embedded Mode

- [ ] `swift run AtticGUI -- --embedded` starts successfully
- [ ] Emulator runs directly (no server needed)
- [ ] Video and audio work identically to client mode

### 2.3 Window Controls

- [ ] Window can be resized
- [ ] Close button terminates application
- [ ] Minimize works correctly

---

## 3. Keyboard Input Tests

### 3.1 Basic Keys
- [ ] A-Z keys produce correct characters
- [ ] 0-9 keys work correctly
- [ ] Space bar works
- [ ] Return/Enter key works
- [ ] Backspace deletes characters
- [ ] Tab key works

### 3.2 Special Keys
- [ ] F1 triggers START (observe emulator response)
- [ ] F2 triggers SELECT
- [ ] F3 triggers OPTION
- [ ] Backtick (`) triggers ATARI key
- [ ] Escape key works
- [ ] Caps Lock toggles caps mode

### 3.3 Modifier Keys
- [ ] Shift produces uppercase/shifted characters
- [ ] Control modifier works (Ctrl+A produces inverse A)
- [ ] Arrow keys move cursor

### 3.4 On-Screen Console Buttons
- [ ] START button is clickable
- [ ] SELECT button is clickable
- [ ] OPTION button is clickable
- [ ] Buttons highlight when corresponding F-key pressed

---

## 4. CLI Tests

### 4.1 Connection

- [ ] `swift run attic` finds running server
- [ ] CLI auto-launches server if not running
- [ ] `swift run attic --socket /path` connects to specific socket
- [ ] Welcome banner displays

### 4.2 Headless Mode

- [ ] `swift run attic --headless` launches server
- [ ] `swift run attic --headless --silent` has no audio
- [ ] REPL prompt appears: `[basic] >`

### 4.3 REPL Commands

#### Basic Mode
- [ ] Enter BASIC line: `10 PRINT "HELLO"`
- [ ] `LIST` displays entered program
- [ ] `RUN` executes program
- [ ] `NEW` clears program
- [ ] `.monitor` switches to monitor mode
- [ ] `.dos` switches to DOS mode

#### Monitor Mode
- [ ] `r` displays registers
- [ ] `m $E000 16` displays memory
- [ ] `d $E000` disassembles memory
- [ ] `bp $0600` sets breakpoint
- [ ] `bl` lists breakpoints
- [ ] `bc $0600` clears breakpoint
- [ ] `s` single-steps
- [ ] `g` resumes execution
- [ ] `.basic` returns to BASIC mode

#### DOS Mode
- [ ] `mount 1 /path/to/disk.atr` mounts disk
- [ ] `dir` lists files
- [ ] `dir *.COM` filters by pattern
- [ ] `type FILENAME.TXT` displays file
- [ ] `dump FILENAME.BIN` shows hex dump
- [ ] `info FILENAME.EXT` shows file info
- [ ] `unmount 1` unmounts disk
- [ ] `.basic` returns to BASIC mode

---

## 5. AESP Protocol Tests

### 5.1 Control Channel (Port 47800)

Using netcat: `nc localhost 47800`

- [ ] Send PING, receive PONG
  - Send: `0xAE 0x50 0x01 0x00 0x00 0x00 0x00 0x00`
  - Expect: Response with type 0x01 (PONG)

- [ ] Send PAUSE, receive ACK
  - Send header with type 0x02
  - Expect: ACK with payload 0x02

- [ ] Send RESUME, receive ACK
  - Send header with type 0x03
  - Expect: ACK with payload 0x03

- [ ] Send STATUS, receive state
  - Send header with type 0x05
  - Expect: Response with running/paused state

### 5.2 Video Channel (Port 47801)

- [ ] Connect to video port
- [ ] Subscribe to video (send VIDEO_SUBSCRIBE)
- [ ] Receive FRAME_RAW messages
- [ ] Verify frame size is 368,640 bytes
- [ ] Unsubscribe stops frame delivery

### 5.3 Audio Channel (Port 47802)

- [ ] Connect to audio port
- [ ] Subscribe to audio (send AUDIO_SUBSCRIBE)
- [ ] Receive AUDIO_PCM messages
- [ ] Verify samples are 16-bit PCM

### 5.4 Error Handling

- [ ] Invalid magic number returns ERROR
- [ ] Invalid version returns ERROR
- [ ] Unknown message type returns ERROR

---

## 6. CLI Protocol Tests

### 6.1 Socket Communication

Using socat: `socat - UNIX-CONNECT:/tmp/attic-<pid>.sock`

- [ ] `CMD:ping` returns `OK:pong`
- [ ] `CMD:pause` returns `OK:paused`
- [ ] `CMD:resume` returns `OK:resumed`
- [ ] `CMD:status` returns status string
- [ ] `CMD:reset cold` resets emulator
- [ ] Invalid command returns `ERR:...`

### 6.2 Memory Operations

- [ ] `CMD:read $0600 16` returns memory bytes
- [ ] `CMD:write $0600 A9,00,60` writes memory
- [ ] Read back written bytes to verify

### 6.3 Register Operations

- [ ] `CMD:registers` shows all registers
- [ ] `CMD:registers A=$50` sets A register
- [ ] Read back to verify

---

## 7. Disassembler Tests

### 7.1 Basic Disassembly

- [ ] `d $E000` shows ROM code
- [ ] Address, bytes, mnemonic, operand displayed
- [ ] Known labels appear (DMACTL, POKEY, etc.)

### 7.2 Addressing Modes

- [ ] Immediate: `LDA #$00`
- [ ] Zero Page: `LDA $00`
- [ ] Absolute: `LDA $E000`
- [ ] Indexed X: `LDA $E000,X`
- [ ] Indexed Y: `LDA $E000,Y`
- [ ] Indirect: `JMP ($FFFC)`
- [ ] Indexed Indirect: `LDA ($00,X)`
- [ ] Indirect Indexed: `LDA ($00),Y`
- [ ] Relative: `BNE $E010 (+5)` with offset

### 7.3 Illegal Opcodes

- [ ] Illegal opcodes are marked
- [ ] LAX, SAX, DCP, etc. disassemble correctly

---

## 8. Monitor/Debugger Tests

### 8.1 Breakpoints

- [ ] Set breakpoint at RAM address
- [ ] Run code to breakpoint
- [ ] Emulator pauses at breakpoint
- [ ] Breakpoint hit message shows address and registers
- [ ] Clear breakpoint works
- [ ] Code continues past cleared breakpoint

### 8.2 Stepping

- [ ] Single step executes one instruction
- [ ] Step count (s 10) executes 10 instructions
- [ ] Step over (so) steps over JSR
- [ ] Until (until $XXXX) runs to address

### 8.3 Assembler

- [ ] `a $0600` enters assembly mode
- [ ] Enter `LDA #$00`, see bytes assembled
- [ ] Labels work: `LOOP LDA #$00`
- [ ] Forward references resolve
- [ ] `END` or empty line exits assembly mode
- [ ] Assembled code executes correctly

---

## 9. ATR/DOS Tests

### 9.1 Disk Mounting

- [ ] Mount single density disk
- [ ] Mount enhanced density disk
- [ ] Mount double density disk
- [ ] Mount read-only (quad density)
- [ ] Invalid file shows error

### 9.2 Directory Operations

- [ ] List all files
- [ ] Wildcard patterns work: `*.COM`, `TEST?.BAS`
- [ ] File sizes shown correctly
- [ ] Locked files marked

### 9.3 File Operations

- [ ] Read file content (type)
- [ ] Hex dump file (dump)
- [ ] Export file to host filesystem
- [ ] Import file from host filesystem
- [ ] Delete file
- [ ] Rename file
- [ ] Lock/Unlock file

### 9.4 Disk Creation

- [ ] Create new single density disk
- [ ] Create new enhanced density disk
- [ ] Create new double density disk
- [ ] Format existing disk

---

## 10. BASIC Mode Tests

### 10.1 Line Entry

- [ ] Enter numbered lines
- [ ] Lines tokenize correctly
- [ ] Abbreviations expand (PR. -> PRINT)
- [ ] Invalid syntax shows error

### 10.2 Program Management

- [ ] LIST shows entire program
- [ ] LIST 10-20 shows line range
- [ ] RUN executes program
- [ ] NEW clears program
- [ ] Delete line by entering number only

### 10.3 Tokenization Round-trip

- [ ] Enter program: `10 PRINT "HELLO":GOTO 10`
- [ ] LIST shows identical text
- [ ] RUN works correctly

### 10.4 Complex Programs

- [ ] FOR/NEXT loops
- [ ] IF/THEN statements
- [ ] GOSUB/RETURN
- [ ] Arrays (DIM)
- [ ] String operations
- [ ] Mathematical expressions

---

## 11. State Persistence Tests

### 11.1 Save State

- [ ] `state save /path/to/file.attic` creates file
- [ ] File is ~210KB+ (includes metadata)
- [ ] Error on invalid path

### 11.2 Load State

- [ ] `state load /path/to/file.attic` restores state
- [ ] Screen content restored
- [ ] Memory content restored
- [ ] REPL mode restored
- [ ] Error on invalid file
- [ ] Error on wrong format version

### 11.3 State Integrity

- [ ] Save mid-game, modify state, load restores original
- [ ] Multiple save/load cycles work

---

## 12. Performance Tests

### 12.1 Frame Rate

- [ ] GUI maintains 60fps during emulation
- [ ] No frame drops during normal operation
- [ ] Status bar shows consistent frame rate

### 12.2 Audio Latency

- [ ] Keyclick responds within ~50ms
- [ ] No audio buffer underruns
- [ ] Audio stays in sync over extended periods

### 12.3 Memory Usage

- [ ] Application memory stays stable over time
- [ ] No memory leaks during extended sessions
- [ ] Large disk operations don't cause spikes

---

## 13. Error Handling Tests

### 13.1 Missing ROMs

- [ ] Clear error message when ROMs not found
- [ ] Suggestion for ROM location

### 13.2 Invalid Files

- [ ] Invalid ATR file shows error
- [ ] Corrupt state file shows error
- [ ] Error includes filename

### 13.3 Network Errors

- [ ] Server not found shows helpful message
- [ ] Connection timeout handled gracefully
- [ ] Reconnection possible after error

---

## 14. Multi-Client Tests

### 14.1 Multiple GUI Clients

- [ ] Start AtticServer
- [ ] Connect first GUI client
- [ ] Connect second GUI client
- [ ] Both receive video frames
- [ ] Both receive audio samples
- [ ] Input from either client works

### 14.2 CLI and GUI Together

- [ ] Start AtticServer
- [ ] Connect GUI client
- [ ] Connect CLI client
- [ ] CLI commands affect GUI display
- [ ] Both can pause/resume

---

## Test Results Template

| Test Section | Pass | Fail | Notes |
|--------------|------|------|-------|
| 1. AtticServer | | | |
| 2. AtticGUI | | | |
| 3. Keyboard Input | | | |
| 4. CLI | | | |
| 5. AESP Protocol | | | |
| 6. CLI Protocol | | | |
| 7. Disassembler | | | |
| 8. Monitor/Debugger | | | |
| 9. ATR/DOS | | | |
| 10. BASIC Mode | | | |
| 11. State Persistence | | | |
| 12. Performance | | | |
| 13. Error Handling | | | |
| 14. Multi-Client | | | |

---

## Regression Testing

After any code changes, re-run the following critical tests:

1. Server starts and accepts connections
2. GUI displays video and plays audio
3. Keyboard input works
4. CLI REPL responds to commands
5. Disk mount/list/read works
6. State save/load works

---

## Known Limitations

The following features are not yet implemented and should not be tested:

- Game controller support (Phase 17)
- Screenshot capture (Phase 17)
- BASIC injection via server (Phase 17)
- Keyboard injection via server (Phase 17)
- File open dialogs (Phase 17)
- WebSocket bridge (Phase 18)
- Web browser client (Phase 19)

See [FUTURE_IMPLEMENTATION.md](FUTURE_IMPLEMENTATION.md) for details.
