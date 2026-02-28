# Plan: Porting AtticServer to Clojure

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Overview](#2-architecture-overview)
3. [FFI Strategy: libatari800 Integration](#3-ffi-strategy-libatari800-integration)
4. [Project Structure & Build](#4-project-structure--build)
5. [Phase Plan](#5-phase-plan)
6. [Module-by-Module Porting Guide](#6-module-by-module-porting-guide)
7. [Concurrency Model](#7-concurrency-model)
8. [Testing Strategy](#8-testing-strategy)
9. [Risk Analysis](#9-risk-analysis)
10. [Open Questions](#10-open-questions)

---

## 1. Executive Summary

Port AtticServer from Swift to Clojure as a **wire-compatible drop-in replacement**.
Existing clients (AtticGUI, AtticCLI) must work unmodified against the Clojure server.

**Scope**: Full port — AESP binary protocol, CLI text protocol (50+ commands),
emulation loop, BASIC tokenizer, 6502 assembler/disassembler, ATR filesystem,
state save/load, screenshot generation.

**FFI approach**: JNA calling libatari800 compiled as a shared library (.dylib/.so).

**Estimated effort**: 8-12 phases, roughly 2,000-4,000 lines of Clojure + build scripts.

---

## 2. Architecture Overview

### Current Swift Architecture

```
┌─────────────────────────────────────────────────┐
│                  AtticServer.swift               │
│         (main loop, delegates, CLI commands)     │
│                  ~1,650 lines                    │
└───────┬──────────────┬──────────────┬────────────┘
        │              │              │
   ┌────▼────┐   ┌─────▼─────┐  ┌────▼────────┐
   │AtticCore│   │AtticProto- │  │ Foundation  │
   │         │   │ col        │  │ CoreGraphics│
   │EmulatorE│   │AESPServer  │  │ ImageIO     │
   │ngine    │   │AESPMessage │  └─────────────┘
   │AudioEng │   │CLISocket   │
   │DiskMgr  │   │Server      │
   │Breakpts │   └────────────┘
   └────┬────┘
        │
   ┌────▼────────┐
   │ libatari800 │
   │  (C library) │
   └─────────────┘
```

### Target Clojure Architecture

```
┌──────────────────────────────────────────────────┐
│              attic-server (Clojure)               │
│                                                   │
│  ┌──────────┐  ┌──────────┐  ┌────────────────┐  │
│  │  main.clj│  │aesp/     │  │ cli/           │  │
│  │  (entry) │  │server.clj│  │ server.clj     │  │
│  │          │  │message.clj│ │ commands.clj   │  │
│  └────┬─────┘  └────┬─────┘  └───────┬────────┘  │
│       │              │                │            │
│  ┌────▼──────────────▼────────────────▼─────────┐ │
│  │              emulator.clj                     │ │
│  │   (engine state, frame loop, input, memory)   │ │
│  └──────────────────┬────────────────────────────┘ │
│                     │                              │
│  ┌──────────────────▼────────────────────────────┐ │
│  │            libatari800.clj (JNA bindings)      │ │
│  └──────────────────┬────────────────────────────┘ │
└─────────────────────┼──────────────────────────────┘
                      │
                ┌─────▼──────┐
                │libatari800 │
                │ .dylib/.so │
                └────────────┘
```

### Key Design Principles

1. **Atoms for mutable state** — emulator run-state, client lists, breakpoints
2. **core.async channels** — message passing between server threads and emulator
3. **Protocols (Clojure)** — define interfaces for memory bus, server delegate
4. **Records/maps for data** — AESP messages, CPU registers, configuration
5. **Java NIO** — TCP server sockets for AESP (or Aleph/Netty for higher perf)
6. **JNA** — C FFI to libatari800

---

## 3. FFI Strategy: libatari800 Integration

### Recommended: JNA + Shared Library

Recompile libatari800 from the [atari800 source](https://github.com/atari800/atari800) as
a shared library (`.dylib` on macOS, `.so` on Linux):

```bash
# Build libatari800 as shared library
cd atari800/src
./configure --target=default --enable-lib
make
gcc -shared -o libatari800.dylib *.o -framework CoreFoundation  # macOS
# gcc -shared -o libatari800.so *.o                              # Linux
```

### JNA Interface Definition

```clojure
(ns attic.native.libatari800
  (:import [com.sun.jna Native Pointer Memory]
           [com.sun.jna.ptr IntByReference]))

;; Define the C function signatures
(gen-interface
  :name attic.native.ILibAtari800
  :extends [com.sun.jna.Library]
  :methods [
    [libatari800_init [int (class "[Ljava.lang.String;")] int]
    [libatari800_next_frame [Pointer] int]
    [libatari800_get_main_memory_ptr [] Pointer]
    [libatari800_get_screen_ptr [] Pointer]
    [libatari800_get_sound_buffer [] Pointer]
    [libatari800_get_current_state [Pointer] void]
    [libatari800_restore_state [Pointer] void]
    [libatari800_mount_disk_image [int String] int]
    [libatari800_reboot_with_file [String] void]
  ])

;; Load the library
(def lib
  (Native/load "atari800" attic.native.ILibAtari800))
```

### Input Template Struct (JNA)

The `input_template_t` C struct must be mapped via JNA `Structure`:

```clojure
(gen-class
  :name attic.native.InputTemplate
  :extends com.sun.jna.Structure
  :state state
  :init init
  :prefix "input-"
  :methods [[getFieldOrder [] java.util.List]])
```

Or more practically, use `com.sun.jna.Structure` with field annotations.
The struct has fields for: `keychar`, `keycode`, `shift`, `control`,
`start`, `select`, `option`, `special`, `joy0`, `joy1`, `trig0`, `trig1`.

### Thread Safety

libatari800 is **not thread-safe**. All calls must be serialized.
In the Swift version, the `EmulatorEngine` actor guarantees this.
In Clojure, we use a **single-threaded executor** or a **locking agent**:

```clojure
;; Option A: Single-threaded executor (recommended)
(def emu-executor (java.util.concurrent.Executors/newSingleThreadExecutor))

(defn emu-call [f]
  (.get (.submit emu-executor ^Callable f)))

;; All libatari800 calls go through emu-call:
(emu-call #(.libatari800_next_frame lib input-ptr))
```

---

## 4. Project Structure & Build

### Directory Layout

```
attic-server-clj/
├── deps.edn                    # Dependencies and build config
├── build.clj                   # Build script (tools.build)
├── Makefile                    # Convenience targets
├── resources/
│   └── ROM/                    # Atari ROMs (user-provided)
├── native/
│   ├── build-libatari800.sh    # Script to compile .dylib/.so
│   └── libatari800.dylib       # Pre-built native library
├── src/
│   └── attic/
│       ├── main.clj            # Entry point, arg parsing, main loop
│       ├── config.clj          # Server configuration
│       ├── emulator/
│       │   ├── engine.clj      # EmulatorEngine equivalent
│       │   ├── native.clj      # JNA bindings to libatari800
│       │   ├── memory.clj      # Memory bus protocol + helpers
│       │   ├── registers.clj   # CPURegisters record
│       │   ├── breakpoints.clj # BreakpointManager
│       │   ├── input.clj       # InputState, key mapping
│       │   └── state.clj       # State save/load (persistence)
│       ├── protocol/
│       │   ├── aesp.clj        # AESP message types, encode/decode
│       │   ├── server.clj      # AESPServer (3-port TCP listener)
│       │   └── constants.clj   # Magic, ports, opcodes
│       ├── cli/
│       │   ├── server.clj      # CLISocketServer (Unix domain socket)
│       │   ├── commands.clj    # CLI command parsing + dispatch
│       │   └── format.clj      # Response formatting helpers
│       ├── basic/
│       │   ├── tokenizer.clj   # BASIC tokenizer
│       │   ├── detokenizer.clj # BASIC detokenizer (LIST)
│       │   ├── handler.clj     # BASICLineHandler equivalent
│       │   └── variables.clj   # BASIC variable reader
│       ├── asm/
│       │   ├── assembler.clj   # 6502 assembler
│       │   ├── disassembler.clj# 6502 disassembler
│       │   └── labels.clj      # Atari address labels
│       ├── disk/
│       │   ├── manager.clj     # DiskManager
│       │   ├── atr.clj         # ATR file format parser/writer
│       │   └── dos.clj         # DOS filesystem operations
│       └── util/
│           ├── screenshot.clj  # PNG screenshot generation
│           └── hex.clj         # Hex formatting utilities
└── test/
    └── attic/
        ├── protocol/
        │   ├── aesp_test.clj   # AESP encode/decode tests
        │   └── server_test.clj # Server integration tests
        ├── emulator/
        │   └── engine_test.clj
        ├── basic/
        │   ├── tokenizer_test.clj
        │   └── detokenizer_test.clj
        ├── asm/
        │   ├── assembler_test.clj
        │   └── disassembler_test.clj
        └── disk/
            └── atr_test.clj
```

### deps.edn

```clojure
{:paths ["src" "resources"]
 :deps {org.clojure/clojure       {:mvn/version "1.12.0"}
        org.clojure/core.async    {:mvn/version "1.7.701"}
        net.java.dev.jna/jna      {:mvn/version "5.15.0"}
        org.clojure/tools.cli     {:mvn/version "1.1.230"}
        org.clojure/tools.logging {:mvn/version "1.3.0"}
        ch.qos.logback/logback-classic {:mvn/version "1.5.6"}}

 :aliases
 {:run  {:main-opts ["-m" "attic.main"]}
  :test {:extra-paths ["test"]
         :extra-deps {lambdaisland/kaocha {:mvn/version "1.91.1392"}}
         :main-opts ["-m" "kaocha.runner"]}
  :build {:deps {io.github.clojure/tools.build {:mvn/version "0.10.5"}}
          :ns-default build}
  :uberjar {:main-opts ["-m" "build/uber"]}}}
```

---

## 5. Phase Plan

### Phase 1: Foundation — JNA Bindings & Emulator Engine

**Goal**: Initialize libatari800, execute frames, read/write memory.

**Files to create**:
- `attic.emulator.native` — JNA interface, input template struct, library loading
- `attic.emulator.engine` — init, execute-frame, pause/resume, memory read/write
- `attic.emulator.registers` — CPURegisters record
- `attic.emulator.memory` — MemoryBus protocol
- `attic.config` — ROM path discovery, server configuration
- `attic.main` — CLI arg parsing, basic startup

**Swift files being ported**:
- `LibAtari800Wrapper.swift` → `attic.emulator.native`
- `EmulatorEngine.swift` → `attic.emulator.engine`
- `CPURegisters.swift` → `attic.emulator.registers`
- `MemoryBus.swift` → `attic.emulator.memory`

**Milestone**: Can initialize emulator, execute 60 frames, read memory at $E000.

**Estimated LOC**: ~500-700 Clojure

### Phase 2: AESP Protocol — Message Encoding/Decoding

**Goal**: Implement the AESP binary wire format.

**Files to create**:
- `attic.protocol.constants` — magic (0xAE50), opcodes, ports, frame dimensions
- `attic.protocol.aesp` — encode/decode functions, message constructors

**Key implementation details**:
- 8-byte header: magic (2) + version (1) + type (1) + length (4), all big-endian
- Use `java.nio.ByteBuffer` with `ByteOrder/BIG_ENDIAN` for encoding
- All 25 message types with their specific payload parsers
- `message-size` function for receive buffering (check if complete message available)

**Swift files being ported**:
- `AESPMessage.swift` → `attic.protocol.aesp`
- `AESPConstants.swift` → `attic.protocol.constants`

**Milestone**: Round-trip encode/decode all message types. Unit tests passing.

**Estimated LOC**: ~300-400 Clojure

### Phase 3: AESP Server — TCP Listeners on 3 Ports

**Goal**: Accept client connections on control/video/audio ports.

**Files to create**:
- `attic.protocol.server` — AESPServer using Java NIO ServerSocketChannel
  (or Aleph/Netty for async TCP)

**Key implementation details**:
- Three `ServerSocketChannel` instances (ports 47800, 47801, 47802)
- Client tracking: `(atom {uuid {:channel ch, :port :control}})` per port
- Message receive loop with buffering (accumulate bytes until `message-size` returns non-nil)
- Delegate pattern → Clojure multimethod or protocol for message dispatch
- `broadcast-frame` and `broadcast-audio` functions that write to all video/audio clients

**Swift files being ported**:
- `AESPServer.swift` → `attic.protocol.server`

**Milestone**: GUI client can connect on all 3 ports, receives PONG for PING.

**Estimated LOC**: ~400-600 Clojure

### Phase 4: Main Emulation Loop + Video/Audio Broadcast

**Goal**: 60fps frame loop broadcasting video and audio to clients.

**Implementation in `attic.main`**:
- Frame timing loop (~16.67ms per frame) using `System/nanoTime`
- Each frame: execute frame → get BGRA buffer → broadcast to video clients
- Audio: get audio samples → broadcast to audio clients
- Graceful shutdown on SIGINT/SIGTERM (via `sun.misc.Signal` or shutdown hook)

**Key implementation details**:
- BGRA frame buffer is 336×240×4 = 322,560 bytes (from libatari800 screen ptr)
- NTSC palette conversion: indexed color → BGRA (256-entry lookup table)
- Audio: ~735 samples per frame at 44.1kHz, 16-bit signed PCM

**Swift files being ported**:
- `AtticServer.swift` main loop → `attic.main`

**Milestone**: GUI client displays live Atari screen at 60fps with audio.

**Estimated LOC**: ~200-300 Clojure

### Phase 5: AESP Control Message Handling

**Goal**: Handle all control + input messages from GUI clients.

**Implementation in `attic.protocol.server` (or a delegate namespace)**:
- PAUSE/RESUME/RESET → call emulator engine
- KEY_DOWN/KEY_UP → update input state
- JOYSTICK/CONSOLE_KEYS/PADDLE → update input state
- STATUS → query emulator state, format response with disk info
- BOOT_FILE → load file, reboot emulator
- ACK/ERROR responses

**Swift files being ported**:
- `ServerDelegate` in `AtticServer.swift` → message handler in server

**Milestone**: Full GUI interaction — pause/resume, keyboard, joystick, reset.

**Estimated LOC**: ~200-300 Clojure

### Phase 6: CLI Socket Server + Basic Commands

**Goal**: Unix domain socket server with text protocol.

**Files to create**:
- `attic.cli.server` — Unix socket listener using `java.net.UnixDomainSocketAddress`
  (Java 16+) or JNA for older JVMs
- `attic.cli.commands` — command parsing and dispatch
- `attic.cli.format` — response formatting

**Key implementation details**:
- Socket at `/tmp/attic-<pid>.sock`
- Text protocol: `CMD:command args\n` → `OK:result\n` or `ERR:message\n`
- Multi-line responses use `\x1E` (record separator) between lines
- Commands: ping, version, pause, resume, step, reset, boot, status, quit, shutdown

**Swift files being ported**:
- `CLISocketServer` in AtticProtocol → `attic.cli.server`
- `CLIServerDelegate` in `AtticServer.swift` → `attic.cli.commands`

**Milestone**: `attic --repl` can connect and control emulator via text commands.

**Estimated LOC**: ~400-500 Clojure

### Phase 7: Memory, Registers, Breakpoints

**Goal**: Full memory/register/breakpoint CLI commands.

**Files to create/extend**:
- `attic.emulator.breakpoints` — BreakpointManager (BRK injection + PC watching)

**CLI commands**: read, write, fill, registers, breakpoint set/clear/list, disassemble

**Key implementation details**:
- BRK injection ($00) for RAM breakpoints, PC polling for ROM breakpoints
- Memory map classification: $0000-$BFFF = RAM, $C000+ = ROM
- Breakpoint check in frame loop (poll PC after each frame)

**Swift files being ported**:
- `BreakpointManager.swift` → `attic.emulator.breakpoints`
- Memory/register/breakpoint commands from `CLIServerDelegate`

**Milestone**: Debugger workflow works — set breakpoint, run, hit breakpoint, inspect.

**Estimated LOC**: ~300-400 Clojure

### Phase 8: 6502 Assembler & Disassembler

**Goal**: Port the assembler and disassembler.

**Files to create**:
- `attic.asm.disassembler` — 6502 instruction decoding + formatting
- `attic.asm.assembler` — 6502 instruction encoding (text → bytes)
- `attic.asm.labels` — Atari hardware address labels (POKEY, GTIA, etc.)

**CLI commands**: disassemble, assemble (interactive + single-line), stepover, until

**Key implementation details**:
- 151 valid opcodes → addressing mode + mnemonic lookup table
- Disassembler: read 1-3 bytes, decode opcode, format with labels
- Assembler: parse mnemonic + operand, determine addressing mode, encode
- Interactive assembly sessions tracked per client UUID

**Swift files being ported**:
- `Disassembler.swift` → `attic.asm.disassembler`
- `Assembler.swift` → `attic.asm.assembler`
- `AddressLabels.swift` → `attic.asm.labels`

**Milestone**: Can disassemble ROM code and assemble small programs.

**Estimated LOC**: ~500-700 Clojure

### Phase 9: ATR Filesystem & Disk Management

**Goal**: Port ATR disk image parser and DOS filesystem operations.

**Files to create**:
- `attic.disk.atr` — ATR header parsing, sector read/write, disk creation
- `attic.disk.dos` — Atari DOS 2.0S filesystem (directory, file read/write)
- `attic.disk.manager` — DiskManager (mount/unmount, coordinate with emulator)

**CLI commands**: mount, unmount, drives, dir, type, dump, copy, rename, delete,
lock, unlock, export, import, newdisk, format

**Key implementation details**:
- ATR format: 16-byte header + sector data (128 or 256 bytes/sector)
- DOS 2.0S: VTOC at sectors 360-361, directory at sectors 361-368
- 8.3 filenames, file chains via sector links
- Three density types: SD (720 sectors × 128), ED (1040 × 128), DD (720 × 256)

**Swift files being ported**:
- `ATRParser.swift` → `attic.disk.atr`
- `ATRFileSystem.swift` → `attic.disk.dos`
- `DiskManager.swift` → `attic.disk.manager`

**Milestone**: Can mount ATR, list directory, read/write files, create new disks.

**Estimated LOC**: ~600-800 Clojure

### Phase 10: BASIC Tokenizer & Detokenizer

**Goal**: Port BASIC program handling.

**Files to create**:
- `attic.basic.tokenizer` — Atari BASIC source → tokenized binary
- `attic.basic.detokenizer` — Tokenized binary → source listing
- `attic.basic.handler` — BASICLineHandler (list, export, import, vars, info)
- `attic.basic.variables` — BASIC variable table reader

**CLI commands**: list, basicinfo, basicvars, basicvar, basicexport, basicimport,
basicdelete, basicrenumber, basicsave, basicload, basicstop, basiccont

**Key implementation details**:
- Atari BASIC token table (commands, functions, operators)
- Variable name table and value table in emulator memory
- BCD floating-point format for numeric variables
- Import/export between tokenized memory and text source files

**Swift files being ported**:
- `BASICTokenizer.swift` → `attic.basic.tokenizer`
- `BASICDetokenizer.swift` → `attic.basic.detokenizer`
- `BASICLineHandler.swift` → `attic.basic.handler`

**Milestone**: Can list BASIC program, export to file, import and tokenize.

**Estimated LOC**: ~500-700 Clojure

### Phase 11: Screenshot, Screen Text, Key Injection

**Goal**: Port remaining server features.

**Files to create/extend**:
- `attic.util.screenshot` — BGRA → PNG using `javax.imageio.ImageIO`
- Screen text reading (GRAPHICS 0 screen RAM → Unicode)
- Key injection (type characters via emulated keystrokes)

**CLI commands**: screenshot, screentext, injectkeys

**Key implementation details**:
- PNG generation: create `BufferedImage(TYPE_INT_ARGB)`, set pixels from BGRA buffer,
  write via `ImageIO.write(img, "png", file)`
- Screen code → ATASCII → Unicode mapping (different from ASCII!)
- Key injection: press key → execute N frames → release → execute N frames

**Swift files being ported**:
- Screenshot/screentext/injectkeys handlers in `AtticServer.swift`

**Milestone**: Screenshot saves PNG, screentext returns display content.

**Estimated LOC**: ~200-300 Clojure

### Phase 12: State Save/Load & Polish

**Goal**: State persistence and final integration.

**Files to create/extend**:
- `attic.emulator.state` — save/load emulator state (~210KB snapshots)

**CLI commands**: statesave, stateload

**Key implementation details**:
- State format: metadata header + raw libatari800 state blob
- Metadata: timestamp, REPL mode, mounted disks, frame count
- Binary format must match Swift version for cross-compatibility (or document divergence)

**Milestone**: Full feature parity with Swift AtticServer.

**Estimated LOC**: ~200-300 Clojure

---

## 6. Module-by-Module Porting Guide

### Swift → Clojure Mapping

| Swift Concept | Clojure Equivalent |
|---------------|-------------------|
| `actor EmulatorEngine` | Atom + single-threaded executor |
| `struct CPURegisters` | `defrecord CPURegisters [a x y s p pc]` |
| `enum EmulatorRunState` | Keyword (`:running`, `:paused`, `:breakpoint`, `:uninitialized`) |
| `protocol MemoryBus` | `defprotocol MemoryBus (read-byte [this addr]) (write-byte [this addr val])` |
| `class AESPServer` | Atom of state + NIO channels + core.async |
| `struct AESPMessage` | Map `{:type :ping, :payload (byte-array 0)}` |
| `enum AESPMessageType` | Keyword namespace `:aesp/ping`, `:aesp/pong`, etc. |
| `class CLISocketServer` | Unix domain socket + line reader |
| `enum CLICommand` | Parsed vector `[:read 0x600 16]` or map |
| `enum CLIResponse` | Map `{:status :ok, :data "pong"}` |
| `NSLock` | `java.util.concurrent.locks.ReentrantLock` or atom |
| `Task { }` | `future` or `core.async/go` |
| `async/await` | core.async channels or `deref` on futures |
| `DispatchSource.makeSignalSource` | `sun.misc.Signal/handle` or shutdown hook |
| `Data` (Foundation) | `byte-array` / `java.nio.ByteBuffer` |
| `URL` (Foundation) | `java.io.File` / `java.nio.file.Path` |
| `CGImage` / `ImageIO` | `java.awt.image.BufferedImage` / `javax.imageio.ImageIO` |
| `UUID` | `java.util.UUID` |

### AESP Message Encoding Example

```clojure
(ns attic.protocol.aesp
  (:import [java.nio ByteBuffer ByteOrder]))

(def magic 0xAE50)
(def version 0x01)
(def header-size 8)

(defn encode-message
  "Encode an AESP message to a byte array.
   message is a map with :type (keyword) and :payload (byte-array)."
  [{:keys [type payload]}]
  (let [opcode  (type->opcode type)
        payload (or payload (byte-array 0))
        len     (alength payload)
        buf     (ByteBuffer/allocate (+ header-size len))]
    (.order buf ByteOrder/BIG_ENDIAN)
    (.putShort buf (short magic))
    (.put buf (byte version))
    (.put buf (byte opcode))
    (.putInt buf len)
    (.put buf ^bytes payload)
    (.array buf)))

(defn decode-message
  "Decode an AESP message from a ByteBuffer.
   Returns [message bytes-consumed] or nil if incomplete."
  [^ByteBuffer buf]
  (when (>= (.remaining buf) header-size)
    (.order buf ByteOrder/BIG_ENDIAN)
    (let [pos    (.position buf)
          magic* (.getShort buf)
          ver    (.get buf)
          opcode (.get buf)
          len    (.getInt buf)]
      (if (>= (.remaining buf) len)
        (let [payload (byte-array len)]
          (.get buf payload)
          [{:type    (opcode->type opcode)
            :payload payload}
           (+ header-size len)])
        (do (.position buf pos) nil)))))  ;; incomplete, rewind
```

### Emulator Engine Example

```clojure
(ns attic.emulator.engine
  (:require [attic.emulator.native :as native]))

;; All mutable emulator state in a single atom
(defonce emu-state
  (atom {:run-state  :uninitialized
         :input      (native/make-input-template)
         :breakpoints #{}
         :frame-count 0}))

;; Single-threaded executor serializes all libatari800 calls
(defonce emu-executor
  (java.util.concurrent.Executors/newSingleThreadExecutor))

(defn emu-call
  "Execute f on the emulator thread, blocking until complete."
  [f]
  (.get (.submit emu-executor ^Callable (fn [] (f)))))

(defn initialize! [rom-path]
  (emu-call #(native/init! rom-path))
  (swap! emu-state assoc :run-state :paused))

(defn execute-frame! []
  (let [input (:input @emu-state)
        result (emu-call #(native/next-frame! input))]
    (swap! emu-state update :frame-count inc)
    result))

(defn get-frame-buffer []
  (emu-call native/get-bgra-frame))

(defn read-memory [addr count]
  (emu-call #(native/read-memory addr count)))
```

---

## 7. Concurrency Model

### Thread Architecture

```
┌──────────────┐
│  Main Thread  │  Frame loop: execute-frame → broadcast → sleep
│  (60fps loop) │
└──────┬───────┘
       │ emu-call (submit to executor)
       ▼
┌──────────────┐
│  Emu Thread   │  Single-threaded executor for libatari800
│  (serialized) │  All C FFI calls happen here
└──────────────┘

┌──────────────┐
│  Control NIO  │  Accept + read on port 47800
│  Thread       │  Dispatch messages via core.async channel
└──────────────┘

┌──────────────┐
│  Video NIO    │  Accept on port 47801, write frames to clients
│  Thread       │
└──────────────┘

┌──────────────┐
│  Audio NIO    │  Accept on port 47802, write audio to clients
│  Thread       │
└──────────────┘

┌──────────────┐
│  CLI Socket   │  Accept + read/write on Unix domain socket
│  Thread       │  One thread per connected CLI client
└──────────────┘
```

### Synchronization

- **Emulator state** (`emu-state` atom): read from any thread, mutations via `swap!`
- **libatari800 calls**: always through `emu-executor` (single-threaded)
- **Client lists**: atoms per port `(atom {uuid connection})`
- **Frame/audio data**: produced by main loop, consumed by NIO write threads.
  Use a `core.async/mult` to fan-out to multiple subscribers.

---

## 8. Testing Strategy

### Unit Tests (Pure Functions)

| Module | What to Test |
|--------|-------------|
| `attic.protocol.aesp` | Encode/decode round-trip for all 25 message types |
| `attic.basic.tokenizer` | Token lookup, line tokenization, edge cases |
| `attic.basic.detokenizer` | Detokenize → re-tokenize round-trip |
| `attic.asm.disassembler` | All 151 opcodes, address label substitution |
| `attic.asm.assembler` | All addressing modes, boundary cases |
| `attic.disk.atr` | ATR header parse, sector read, disk creation |
| `attic.disk.dos` | Directory listing, file read/write, VTOC |
| `attic.emulator.registers` | Formatting, flag extraction |
| `attic.cli.commands` | Command parsing for all 50+ commands |

### Integration Tests

| Test | What it Validates |
|------|-------------------|
| AESP ping-pong | Connect to control port, send PING, verify PONG |
| Video subscription | Subscribe, receive FRAME_RAW, verify 322,560 bytes |
| CLI socket | Connect to Unix socket, send `CMD:ping`, verify `OK:pong` |
| Cross-client | Swift GUI connects to Clojure server, displays frames |
| Full emulation | Boot, run 300 frames, read screen memory, verify READY prompt |

### Compatibility Tests

The existing Swift test suite (`make test-protocol`, `make test-server`) should pass
against the Clojure server with minimal modification (just pointing at the Clojure process
instead of the Swift one). This is the ultimate validation of wire compatibility.

---

## 9. Risk Analysis

### High Risk

| Risk | Impact | Mitigation |
|------|--------|------------|
| **libatari800 JNA incompatibility** | Blocks all progress | Prototype JNA bindings first (Phase 1). Test `init` + `next_frame` before committing. |
| **Input template struct alignment** | Emulator ignores input | Verify C struct layout with `offsetof()`. Print struct bytes from Swift and Clojure, compare. |
| **Frame buffer format mismatch** | GUI shows garbage | Compare byte-for-byte: Swift BGRA output vs Clojure BGRA output for the same frame. |
| **State save/load binary format** | Can't share state files | May need to accept format divergence between Swift and Clojure versions. |

### Medium Risk

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Unix domain sockets on JVM** | CLI protocol broken | Java 16+ has `UnixDomainSocketAddress`. Fall back to TCP localhost if needed. |
| **Thread starvation in frame loop** | GUI freezes, CLI unresponsive | Ensure `Task.yield()` equivalent — `Thread/yield` or short sleeps. |
| **JNA performance for 60fps** | Dropped frames | JNA overhead is ~100ns/call, negligible at 60fps. Profile to confirm. |
| **BASIC tokenizer accuracy** | Wrong tokenization | Port token tables exactly. Run same test cases as Swift suite. |

### Low Risk

| Risk | Impact | Mitigation |
|------|--------|------------|
| **PNG generation** | Screenshots look wrong | `BufferedImage` + `ImageIO` is well-proven. |
| **AESP message parsing** | Connection errors | Straightforward binary format. Extensive unit tests. |
| **ATR format** | Disk operations fail | Well-documented format. Byte-for-byte test against known ATR files. |

---

## 10. Open Questions

1. **State file cross-compatibility**: Should Clojure-saved state files be loadable by the
   Swift server and vice versa? The raw libatari800 state blob is identical, but the metadata
   header format would need to be matched exactly.

2. **Build artifact**: Should the Clojure server be distributed as an uberjar
   (`java -jar attic-server.jar`) or as a native image via GraalVM for faster startup?
   Uberjar is simpler; GraalVM native image has fast startup but JNA compatibility
   requires testing.

3. **Java version minimum**: Java 16+ is needed for `UnixDomainSocketAddress` (CLI protocol
   Unix sockets). Is this acceptable, or should we support older JVMs with a TCP fallback?

4. **Shared library distribution**: Should the native `.dylib`/`.so` be bundled in the
   uberjar (extracted at runtime) or installed separately? Bundling is more convenient but
   platform-specific.

5. **Namespace for the project**: Current Clojure convention suggests reverse-domain
   (e.g., `com.attic.server`). The plan uses `attic.*` for simplicity. Preference?

6. **REPL-driven development**: One of Clojure's biggest strengths is the REPL. Should we
   design the emulator engine to be fully controllable from a Clojure REPL (e.g., nREPL
   server embedded in the process)? This would be a unique advantage over the Swift version.

---

## Summary

| Metric | Estimate |
|--------|----------|
| **Total phases** | 12 |
| **Total estimated LOC** | ~3,800-6,000 Clojure |
| **External dependencies** | 5 (Clojure, core.async, JNA, tools.cli, logback) |
| **Native dependency** | libatari800 (.dylib/.so) |
| **Minimum Java version** | 16+ (for Unix domain sockets) |
| **Wire compatibility** | 100% — same AESP protocol, same CLI protocol |
