// =============================================================================
// MCPToolDefinitions.swift - MCP Tool Definitions for Atari Emulator
// =============================================================================
//
// This file defines all the MCP tools that expose Atari 800 XL emulator
// functionality to Claude Code. These tools allow AI assistants to:
//
// - Read and write emulator memory
// - Get and set CPU registers
// - Execute frames and control emulation
// - Interact with BASIC programs
// - Debug with breakpoints and disassembly
//
// Each tool is defined with a JSON Schema that describes its parameters.
//
// =============================================================================

import Foundation

/// Provides all tool definitions for the Attic MCP server.
enum MCPToolDefinitions {

    /// Returns all available tool definitions.
    static var allTools: [ToolDefinition] {
        return [
            // Emulator Control
            emulatorStatus,
            emulatorPause,
            emulatorResume,
            emulatorReset,
            emulatorBootFile,

            // Memory Access
            emulatorReadMemory,
            emulatorWriteMemory,

            // CPU State
            emulatorGetRegisters,
            emulatorSetRegisters,

            // Execution
            emulatorExecuteFrames,

            // Debugging
            emulatorDisassemble,
            emulatorSetBreakpoint,
            emulatorClearBreakpoint,
            emulatorListBreakpoints,

            // Input
            emulatorPressKey,

            // Display
            emulatorScreenshot,

            // BASIC (read-only tools only - injection tools disabled per attic-ahl)
            emulatorListBasic,

            // Disk Operations
            emulatorMountDisk,
            emulatorUnmountDisk,
            emulatorListDrives,

            // Advanced Debugging
            emulatorStepOver,
            emulatorRunUntil,
            emulatorAssemble,
            emulatorFillMemory,

            // State Management
            emulatorSaveState,
            emulatorLoadState,
        ]
    }

    // MARK: - Emulator Control Tools

    static let emulatorStatus = ToolDefinition(
        name: "emulator_status",
        description: "Get the current status of the Atari 800 XL emulator including running state, program counter, mounted disks, and breakpoints.",
        inputSchema: JSONSchema(type: "object")
    )

    static let emulatorPause = ToolDefinition(
        name: "emulator_pause",
        description: "Pause the emulator. This stops execution and allows memory inspection and debugging.",
        inputSchema: JSONSchema(type: "object")
    )

    static let emulatorResume = ToolDefinition(
        name: "emulator_resume",
        description: "Resume the emulator after it has been paused.",
        inputSchema: JSONSchema(type: "object")
    )

    static let emulatorReset = ToolDefinition(
        name: "emulator_reset",
        description: "Reset the Atari 800 XL emulator. A cold reset clears all memory, while a warm reset preserves memory contents.",
        inputSchema: JSONSchema(
            type: "object",
            properties: [
                "cold": PropertySchema(
                    type: "boolean",
                    description: "If true, perform a cold reset (clears memory). If false, perform a warm reset (preserves memory). Default is true.",
                    default: AnyCodable(true)
                )
            ]
        )
    )

    static let emulatorBootFile = ToolDefinition(
        name: "emulator_boot_file",
        description: "Boot the emulator with a file. Supports disk images (ATR, XFD, ATX, DCM, PRO), executables (XEX, COM, EXE), BASIC programs (BAS, LST), cartridges (ROM, CAR), and cassettes (CAS). The emulator performs a cold start after loading the file.",
        inputSchema: JSONSchema(
            type: "object",
            properties: [
                "path": PropertySchema(
                    type: "string",
                    description: "Absolute path to the file to boot"
                )
            ],
            required: ["path"]
        )
    )

    // MARK: - Memory Access Tools

    static let emulatorReadMemory = ToolDefinition(
        name: "emulator_read_memory",
        description: "Read bytes from the Atari's memory. Returns data as hex string. Address range is 0x0000-0xFFFF.",
        inputSchema: JSONSchema(
            type: "object",
            properties: [
                "address": PropertySchema(
                    type: "integer",
                    description: "Starting address to read from (0-65535 or 0x0000-0xFFFF)",
                    minimum: 0,
                    maximum: 65535
                ),
                "count": PropertySchema(
                    type: "integer",
                    description: "Number of bytes to read (1-256). Default is 16.",
                    minimum: 1,
                    maximum: 256,
                    default: AnyCodable(16)
                )
            ],
            required: ["address"]
        )
    )

    static let emulatorWriteMemory = ToolDefinition(
        name: "emulator_write_memory",
        description: "Write bytes to the Atari's memory. The emulator must be paused first.",
        inputSchema: JSONSchema(
            type: "object",
            properties: [
                "address": PropertySchema(
                    type: "integer",
                    description: "Starting address to write to (0-65535 or 0x0000-0xFFFF)",
                    minimum: 0,
                    maximum: 65535
                ),
                "data": PropertySchema(
                    type: "string",
                    description: "Hex string of bytes to write (e.g., 'A9,00,8D,00,D4' or 'A9 00 8D 00 D4')"
                )
            ],
            required: ["address", "data"]
        )
    )

    // MARK: - CPU State Tools

    static let emulatorGetRegisters = ToolDefinition(
        name: "emulator_get_registers",
        description: "Get the current 6502 CPU register values: A (accumulator), X, Y (index registers), S (stack pointer), P (status flags), PC (program counter).",
        inputSchema: JSONSchema(type: "object")
    )

    static let emulatorSetRegisters = ToolDefinition(
        name: "emulator_set_registers",
        description: "Set 6502 CPU register values. The emulator must be paused first. Only specified registers are modified.",
        inputSchema: JSONSchema(
            type: "object",
            properties: [
                "a": PropertySchema(
                    type: "integer",
                    description: "Accumulator value (0-255)",
                    minimum: 0,
                    maximum: 255
                ),
                "x": PropertySchema(
                    type: "integer",
                    description: "X register value (0-255)",
                    minimum: 0,
                    maximum: 255
                ),
                "y": PropertySchema(
                    type: "integer",
                    description: "Y register value (0-255)",
                    minimum: 0,
                    maximum: 255
                ),
                "s": PropertySchema(
                    type: "integer",
                    description: "Stack pointer value (0-255)",
                    minimum: 0,
                    maximum: 255
                ),
                "p": PropertySchema(
                    type: "integer",
                    description: "Processor status flags (0-255)",
                    minimum: 0,
                    maximum: 255
                ),
                "pc": PropertySchema(
                    type: "integer",
                    description: "Program counter value (0-65535)",
                    minimum: 0,
                    maximum: 65535
                )
            ]
        )
    )

    // MARK: - Execution Tools

    static let emulatorExecuteFrames = ToolDefinition(
        name: "emulator_execute_frames",
        description: "Execute a number of emulator frames (each frame is ~1/60th of a second). Useful for letting the emulator run for a short time. Returns the CPU register state after execution.",
        inputSchema: JSONSchema(
            type: "object",
            properties: [
                "count": PropertySchema(
                    type: "integer",
                    description: "Number of frames to execute (1-3600, which is up to 60 seconds). Default is 1.",
                    minimum: 1,
                    maximum: 3600,
                    default: AnyCodable(1)
                )
            ]
        )
    )

    // MARK: - Debugging Tools

    static let emulatorDisassemble = ToolDefinition(
        name: "emulator_disassemble",
        description: "Disassemble 6502 machine code at a memory address. Shows the instruction bytes, mnemonic, and operands. Useful for debugging and understanding what code is doing.",
        inputSchema: JSONSchema(
            type: "object",
            properties: [
                "address": PropertySchema(
                    type: "integer",
                    description: "Starting address to disassemble from. If not specified, disassembles from current PC.",
                    minimum: 0,
                    maximum: 65535
                ),
                "lines": PropertySchema(
                    type: "integer",
                    description: "Number of instructions to disassemble (1-64). Default is 16.",
                    minimum: 1,
                    maximum: 64,
                    default: AnyCodable(16)
                )
            ]
        )
    )

    static let emulatorSetBreakpoint = ToolDefinition(
        name: "emulator_set_breakpoint",
        description: "Set a breakpoint at a memory address. Execution will pause when the PC reaches this address.",
        inputSchema: JSONSchema(
            type: "object",
            properties: [
                "address": PropertySchema(
                    type: "integer",
                    description: "Address to set breakpoint at (0-65535)",
                    minimum: 0,
                    maximum: 65535
                )
            ],
            required: ["address"]
        )
    )

    static let emulatorClearBreakpoint = ToolDefinition(
        name: "emulator_clear_breakpoint",
        description: "Clear a breakpoint at a memory address.",
        inputSchema: JSONSchema(
            type: "object",
            properties: [
                "address": PropertySchema(
                    type: "integer",
                    description: "Address to clear breakpoint from (0-65535)",
                    minimum: 0,
                    maximum: 65535
                )
            ],
            required: ["address"]
        )
    )

    static let emulatorListBreakpoints = ToolDefinition(
        name: "emulator_list_breakpoints",
        description: "List all currently set breakpoints.",
        inputSchema: JSONSchema(type: "object")
    )

    // MARK: - Input Tools

    static let emulatorPressKey = ToolDefinition(
        name: "emulator_press_key",
        description: "Simulate pressing a key on the Atari keyboard. The key is pressed and then released after one frame. Use for typing characters or triggering BASIC input.",
        inputSchema: JSONSchema(
            type: "object",
            properties: [
                "key": PropertySchema(
                    type: "string",
                    description: "The key to press. Can be: a letter (A-Z), number (0-9), RETURN, SPACE, BREAK, ESC, TAB, DELETE, or special: SHIFT+key, CTRL+key"
                )
            ],
            required: ["key"]
        )
    )

    // MARK: - Display Tools

    static let emulatorScreenshot = ToolDefinition(
        name: "emulator_screenshot",
        description: "Capture a screenshot of the current Atari display and save it as a PNG file. Returns the path where the screenshot was saved.",
        inputSchema: JSONSchema(
            type: "object",
            properties: [
                "path": PropertySchema(
                    type: "string",
                    description: "File path to save the screenshot. If not specified, saves to ~/Desktop/Attic-<timestamp>.png. The path can use ~ for home directory."
                )
            ]
        )
    )

    // MARK: - BASIC Tools

    static let emulatorEnterBasicLine = ToolDefinition(
        name: "emulator_enter_basic_line",
        description: "Enter a BASIC program line into the Atari BASIC interpreter. The line is tokenized and injected into BASIC memory. Example: '10 PRINT \"HELLO\"' or '20 GOTO 10'.",
        inputSchema: JSONSchema(
            type: "object",
            properties: [
                "line": PropertySchema(
                    type: "string",
                    description: "The BASIC line to enter, including line number. Example: '10 PRINT \"HELLO WORLD\"'"
                )
            ],
            required: ["line"]
        )
    )

    static let emulatorRunBasic = ToolDefinition(
        name: "emulator_run_basic",
        description: "Execute the BASIC RUN command to start the BASIC program currently in memory.",
        inputSchema: JSONSchema(type: "object")
    )

    static let emulatorListBasic = ToolDefinition(
        name: "emulator_list_basic",
        description: "List the BASIC program currently in memory. Returns the detokenized source code.",
        inputSchema: JSONSchema(type: "object")
    )

    static let emulatorNewBasic = ToolDefinition(
        name: "emulator_new_basic",
        description: "Clear the BASIC program memory (equivalent to BASIC NEW command).",
        inputSchema: JSONSchema(type: "object")
    )

    // MARK: - Disk Operation Tools

    /// Mounts an ATR disk image to a drive slot (1-8).
    static let emulatorMountDisk = ToolDefinition(
        name: "emulator_mount_disk",
        description: "Mount an ATR disk image to a drive (1-8). The file must be an ATR format disk image.",
        inputSchema: JSONSchema(
            type: "object",
            properties: [
                "drive": PropertySchema(
                    type: "integer",
                    description: "Drive number (1-8)",
                    minimum: 1,
                    maximum: 8
                ),
                "path": PropertySchema(
                    type: "string",
                    description: "Absolute path to the ATR disk image file"
                )
            ],
            required: ["drive", "path"]
        )
    )

    /// Unmounts a disk image from a drive slot.
    static let emulatorUnmountDisk = ToolDefinition(
        name: "emulator_unmount_disk",
        description: "Unmount a disk image from a drive (1-8).",
        inputSchema: JSONSchema(
            type: "object",
            properties: [
                "drive": PropertySchema(
                    type: "integer",
                    description: "Drive number to unmount (1-8)",
                    minimum: 1,
                    maximum: 8
                )
            ],
            required: ["drive"]
        )
    )

    /// Lists all drive slots and their mounted disk images.
    static let emulatorListDrives = ToolDefinition(
        name: "emulator_list_drives",
        description: "List all drives (1-8) and their currently mounted disk images.",
        inputSchema: JSONSchema(type: "object")
    )

    // MARK: - Advanced Debugging Tools

    /// Steps over a JSR instruction, executing the subroutine as a single step.
    static let emulatorStepOver = ToolDefinition(
        name: "emulator_step_over",
        description: "Step over a JSR subroutine call. If the current instruction is JSR, executes the entire subroutine and stops after it returns. Otherwise behaves like a single step.",
        inputSchema: JSONSchema(type: "object")
    )

    /// Runs execution until PC reaches a specific address.
    static let emulatorRunUntil = ToolDefinition(
        name: "emulator_run_until",
        description: "Run the emulator until the program counter reaches the specified address. Similar to a temporary breakpoint.",
        inputSchema: JSONSchema(
            type: "object",
            properties: [
                "address": PropertySchema(
                    type: "integer",
                    description: "Target address to run until (0-65535)",
                    minimum: 0,
                    maximum: 65535
                )
            ],
            required: ["address"]
        )
    )

    /// Assembles a single 6502 instruction and writes it to memory.
    static let emulatorAssemble = ToolDefinition(
        name: "emulator_assemble",
        description: "Assemble a single 6502 instruction and write the resulting bytes to memory. Example: 'LDA #$00' or 'JMP $E459'.",
        inputSchema: JSONSchema(
            type: "object",
            properties: [
                "address": PropertySchema(
                    type: "integer",
                    description: "Address to write the assembled instruction (0-65535)",
                    minimum: 0,
                    maximum: 65535
                ),
                "instruction": PropertySchema(
                    type: "string",
                    description: "6502 assembly instruction to assemble (e.g., 'LDA #$00', 'JMP $E459', 'NOP')"
                )
            ],
            required: ["address", "instruction"]
        )
    )

    /// Fills a memory range with a byte value.
    static let emulatorFillMemory = ToolDefinition(
        name: "emulator_fill_memory",
        description: "Fill a range of memory with a single byte value. The emulator must be paused first.",
        inputSchema: JSONSchema(
            type: "object",
            properties: [
                "start": PropertySchema(
                    type: "integer",
                    description: "Start address of the range (0-65535)",
                    minimum: 0,
                    maximum: 65535
                ),
                "end": PropertySchema(
                    type: "integer",
                    description: "End address of the range, inclusive (0-65535)",
                    minimum: 0,
                    maximum: 65535
                ),
                "value": PropertySchema(
                    type: "integer",
                    description: "Byte value to fill with (0-255)",
                    minimum: 0,
                    maximum: 255
                )
            ],
            required: ["start", "end", "value"]
        )
    )

    // MARK: - State Management Tools

    /// Saves the complete emulator state to a file.
    static let emulatorSaveState = ToolDefinition(
        name: "emulator_save_state",
        description: "Save the complete emulator state to a file. This captures all memory, registers, and hardware state for later restoration.",
        inputSchema: JSONSchema(
            type: "object",
            properties: [
                "path": PropertySchema(
                    type: "string",
                    description: "Absolute path to save the state file"
                )
            ],
            required: ["path"]
        )
    )

    /// Loads a previously saved emulator state from a file.
    static let emulatorLoadState = ToolDefinition(
        name: "emulator_load_state",
        description: "Load a previously saved emulator state from a file. This restores all memory, registers, and hardware state.",
        inputSchema: JSONSchema(
            type: "object",
            properties: [
                "path": PropertySchema(
                    type: "string",
                    description: "Absolute path to the state file to load"
                )
            ],
            required: ["path"]
        )
    )
}
