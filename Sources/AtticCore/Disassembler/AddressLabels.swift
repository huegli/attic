// =============================================================================
// AddressLabels.swift - Known Address Labels for Disassembly
// =============================================================================
//
// This file provides a label table for known addresses in the Atari 800 XL.
// These labels make disassembly output more readable by replacing numeric
// addresses with meaningful names.
//
// Categories of labeled addresses:
// - Hardware registers (GTIA, POKEY, PIA, ANTIC at $D000-$D4FF)
// - OS vectors and entry points ($E000-$FFFF)
// - Zero page OS variables ($00-$FF)
// - Page 2 OS variables ($0200-$02FF)
// - BASIC variables (when BASIC is active)
//
// The AddressLabels struct is used by the Disassembler to substitute labels
// for addresses in branch/jump targets and memory operands.
//
// Reference: Atari 800 XL OS Manual, Mapping the Atari
//
// =============================================================================

import Foundation

/// A table mapping addresses to their symbolic names.
///
/// This structure allows the disassembler to show meaningful labels instead
/// of raw hex addresses. Labels can be looked up by address, and custom
/// labels can be added at runtime.
///
/// Example:
/// ```swift
/// var labels = AddressLabels.atariStandard
/// labels.add(0x0600, "MYCODE")
/// if let name = labels.lookup(0xD40A) {
///     print(name)  // "WSYNC"
/// }
/// ```
public struct AddressLabels: Sendable {
    /// The underlying dictionary mapping addresses to labels.
    private var labels: [UInt16: String]

    /// Creates an empty label table.
    public init() {
        self.labels = [:]
    }

    /// Creates a label table with the given initial labels.
    ///
    /// - Parameter labels: Dictionary of address-to-label mappings.
    public init(labels: [UInt16: String]) {
        self.labels = labels
    }

    /// Looks up the label for an address.
    ///
    /// - Parameter address: The address to look up.
    /// - Returns: The label if one exists, otherwise nil.
    public func lookup(_ address: UInt16) -> String? {
        labels[address]
    }

    /// Adds a label for an address.
    ///
    /// If a label already exists for this address, it will be replaced.
    ///
    /// - Parameters:
    ///   - address: The address to label.
    ///   - label: The label name.
    public mutating func add(_ address: UInt16, _ label: String) {
        labels[address] = label
    }

    /// Removes the label for an address.
    ///
    /// - Parameter address: The address to unlabel.
    /// - Returns: The removed label, if one existed.
    @discardableResult
    public mutating func remove(_ address: UInt16) -> String? {
        labels.removeValue(forKey: address)
    }

    /// Returns all addresses that have labels.
    public var addresses: [UInt16] {
        Array(labels.keys).sorted()
    }

    /// Returns all labels in the table.
    public var allLabels: [(address: UInt16, label: String)] {
        labels.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// Merges another label table into this one.
    ///
    /// Labels from the other table will overwrite existing labels for the
    /// same address.
    ///
    /// - Parameter other: The label table to merge.
    public mutating func merge(_ other: AddressLabels) {
        labels.merge(other.labels) { _, new in new }
    }
}

// =============================================================================
// MARK: - Standard Atari Labels
// =============================================================================

extension AddressLabels {
    /// The standard Atari 800 XL label set including all hardware registers,
    /// OS vectors, and common zero-page locations.
    public static var atariStandard: AddressLabels {
        var labels = AddressLabels()
        labels.merge(hardwareRegisters)
        labels.merge(osVectors)
        labels.merge(zeroPageVariables)
        labels.merge(page2Variables)
        return labels
    }

    /// Only hardware register labels (GTIA, POKEY, PIA, ANTIC).
    public static var hardwareRegisters: AddressLabels {
        var labels = AddressLabels()
        labels.merge(gtiaRegisters)
        labels.merge(pokeyRegisters)
        labels.merge(piaRegisters)
        labels.merge(anticRegisters)
        return labels
    }
}

// =============================================================================
// MARK: - GTIA Registers ($D000-$D01F)
// =============================================================================

extension AddressLabels {
    /// GTIA (Graphics Television Interface Adaptor) registers.
    ///
    /// GTIA handles graphics priority, player-missile graphics, and collision
    /// detection. It also controls some video mode features.
    public static var gtiaRegisters: AddressLabels {
        // Note: GTIA registers have different meanings for read vs write at same addresses.
        // We use combined "Write/Read" naming for dual-purpose registers.
        // Write registers are listed first as they are more commonly used in user code.
        AddressLabels(labels: [
            // $D000-$D007: Write = horizontal position, Read = collision
            0xD000: "HPOSP0/M0PF",   // W: Horizontal position player 0, R: Missile 0 to playfield collision
            0xD001: "HPOSP1/M1PF",   // W: Horizontal position player 1, R: Missile 1 to playfield collision
            0xD002: "HPOSP2/M2PF",   // W: Horizontal position player 2, R: Missile 2 to playfield collision
            0xD003: "HPOSP3/M3PF",   // W: Horizontal position player 3, R: Missile 3 to playfield collision
            0xD004: "HPOSM0/P0PF",   // W: Horizontal position missile 0, R: Player 0 to playfield collision
            0xD005: "HPOSM1/P1PF",   // W: Horizontal position missile 1, R: Player 1 to playfield collision
            0xD006: "HPOSM2/P2PF",   // W: Horizontal position missile 2, R: Player 2 to playfield collision
            0xD007: "HPOSM3/P3PF",   // W: Horizontal position missile 3, R: Player 3 to playfield collision

            // $D008-$D00F: Write = size/graphics, Read = collision
            0xD008: "SIZEP0/M0PL",   // W: Player 0 size, R: Missile 0 to player collision
            0xD009: "SIZEP1/M1PL",   // W: Player 1 size, R: Missile 1 to player collision
            0xD00A: "SIZEP2/M2PL",   // W: Player 2 size, R: Missile 2 to player collision
            0xD00B: "SIZEP3/M3PL",   // W: Player 3 size, R: Missile 3 to player collision
            0xD00C: "SIZEM/P0PL",    // W: Missile sizes (all 4), R: Player 0 to player collision
            0xD00D: "GRAFP0/P1PL",   // W: Player 0 graphics, R: Player 1 to player collision
            0xD00E: "GRAFP1/P2PL",   // W: Player 1 graphics, R: Player 2 to player collision
            0xD00F: "GRAFP2/P3PL",   // W: Player 2 graphics, R: Player 3 to player collision

            // $D010-$D014: Write = graphics/color, Read = trigger/PAL
            0xD010: "GRAFP3/TRIG0",  // W: Player 3 graphics, R: Joystick trigger 0
            0xD011: "GRAFM/TRIG1",   // W: Missile graphics (all 4), R: Joystick trigger 1
            0xD012: "COLPM0/TRIG2",  // W: Player/missile 0 color, R: Joystick trigger 2
            0xD013: "COLPM1/TRIG3",  // W: Player/missile 1 color, R: Joystick trigger 3
            0xD014: "COLPM2/PAL",    // W: Player/missile 2 color, R: PAL/NTSC flag

            // Write-only registers (no read equivalent)
            0xD015: "COLPM3",     // Player/missile 3 color
            0xD016: "COLPF0",     // Playfield 0 color
            0xD017: "COLPF1",     // Playfield 1 color
            0xD018: "COLPF2",     // Playfield 2 color
            0xD019: "COLPF3",     // Playfield 3 color
            0xD01A: "COLBK",      // Background color
            0xD01B: "PRIOR",      // Priority/GTIA mode select
            0xD01C: "VDELAY",     // Vertical delay for P/M graphics
            0xD01D: "GRACTL",     // Graphics control
            0xD01E: "HITCLR",     // Clear collision registers (write)
            0xD01F: "CONSOL",     // Console buttons/speaker
        ])
    }
}

// =============================================================================
// MARK: - POKEY Registers ($D200-$D21F)
// =============================================================================

extension AddressLabels {
    /// POKEY (POtentiometer and KEYboard) registers.
    ///
    /// POKEY handles sound generation, keyboard scanning, serial I/O,
    /// random number generation, and paddle/pot reading.
    public static var pokeyRegisters: AddressLabels {
        // Note: POKEY registers have different meanings for read vs write at same addresses.
        // We use combined "Write/Read" naming for dual-purpose registers.
        // Write registers are listed first as they are more commonly used in user code.
        AddressLabels(labels: [
            // $D200-$D207: Write = audio, Read = pot
            0xD200: "AUDF1/POT0",    // W: Audio frequency 1, R: Potentiometer (paddle) 0
            0xD201: "AUDC1/POT1",    // W: Audio control 1, R: Potentiometer 1
            0xD202: "AUDF2/POT2",    // W: Audio frequency 2, R: Potentiometer 2
            0xD203: "AUDC2/POT3",    // W: Audio control 2, R: Potentiometer 3
            0xD204: "AUDF3/POT4",    // W: Audio frequency 3, R: Potentiometer 4
            0xD205: "AUDC3/POT5",    // W: Audio control 3, R: Potentiometer 5
            0xD206: "AUDF4/POT6",    // W: Audio frequency 4, R: Potentiometer 6
            0xD207: "AUDC4/POT7",    // W: Audio control 4, R: Potentiometer 7

            // $D208-$D20A: Write = control, Read = status
            0xD208: "AUDCTL/ALLPOT", // W: Audio control, R: All pot port status
            0xD209: "STIMER/KBCODE", // W: Start timers, R: Keyboard code
            0xD20A: "SKRES/RANDOM",  // W: Serial/keyboard reset, R: Random number generator

            // Write-only registers
            0xD20B: "POTGO",         // Start pot scan (write only)

            // $D20D-$D20F: Write = serial out/control, Read = serial in/status
            0xD20D: "SEROUT/SERIN",  // W: Serial port output, R: Serial port input
            0xD20E: "IRQEN/IRQST",   // W: IRQ enable, R: IRQ status
            0xD20F: "SKCTL/SKSTAT",  // W: Serial/keyboard control, R: Serial port and keyboard status
        ])
    }
}

// =============================================================================
// MARK: - PIA Registers ($D300-$D303)
// =============================================================================

extension AddressLabels {
    /// PIA (Peripheral Interface Adaptor) registers.
    ///
    /// PIA handles joystick port input and memory/ROM banking control.
    public static var piaRegisters: AddressLabels {
        AddressLabels(labels: [
            0xD300: "PORTA",     // Port A - Joystick ports 1 & 2
            0xD301: "PORTB",     // Port B - Memory/ROM control
            0xD302: "PACTL",     // Port A control
            0xD303: "PBCTL",     // Port B control
        ])
    }
}

// =============================================================================
// MARK: - ANTIC Registers ($D400-$D40F)
// =============================================================================

extension AddressLabels {
    /// ANTIC (Alphanumeric Television Interface Controller) registers.
    ///
    /// ANTIC is the display processor that generates the video display
    /// based on a display list and data from memory.
    public static var anticRegisters: AddressLabels {
        // Note: ANTIC register $D40F has different meanings for read vs write.
        // We use combined "Write/Read" naming for this register.
        AddressLabels(labels: [
            // Write-only registers
            0xD400: "DMACTL",        // DMA control
            0xD401: "CHACTL",        // Character control
            0xD402: "DLISTL",        // Display list low byte
            0xD403: "DLISTH",        // Display list high byte
            0xD404: "HSCROL",        // Horizontal scroll
            0xD405: "VSCROL",        // Vertical scroll
            0xD407: "PMBASE",        // Player/Missile base address (high byte)
            0xD409: "CHBASE",        // Character base address (high byte)
            0xD40A: "WSYNC",         // Wait for horizontal sync
            0xD40E: "NMIEN",         // NMI enable

            // Read-only registers
            0xD40B: "VCOUNT",        // Vertical line counter
            0xD40C: "PENH",          // Light pen horizontal position
            0xD40D: "PENV",          // Light pen vertical position

            // $D40F: Write = reset, Read = status
            0xD40F: "NMIRES/NMIST",  // W: NMI reset, R: NMI status
        ])
    }
}

// =============================================================================
// MARK: - OS Vectors ($E000-$FFFF)
// =============================================================================

extension AddressLabels {
    /// OS vectors and commonly-called ROM routines.
    public static var osVectors: AddressLabels {
        AddressLabels(labels: [
            // Jump vector table in RAM ($0200-$021F)
            0x0200: "VDSLST",    // Display list interrupt vector
            0x0202: "VPRCED",    // Proceed line vector
            0x0204: "VINTER",    // Interrupt line vector
            0x0206: "VBREAK",    // BRK instruction vector
            0x0208: "VKEYBD",    // Keyboard interrupt vector
            0x020A: "VSERIN",    // Serial input ready vector
            0x020C: "VSEROR",    // Serial output ready vector
            0x020E: "VSEROC",    // Serial output complete vector
            0x0210: "VTIMR1",    // Timer 1 vector
            0x0212: "VTIMR2",    // Timer 2 vector
            0x0214: "VTIMR4",    // Timer 4 vector
            0x0216: "VIMIRQ",    // IRQ immediate vector
            0x0218: "CDTMV1",    // Countdown timer 1
            0x021A: "CDTMV2",    // Countdown timer 2
            0x021C: "CDTMV3",    // Countdown timer 3
            0x021E: "CDTMV4",    // Countdown timer 4
            0x0220: "CDTMV5",    // Countdown timer 5
            0x0222: "VVBLKI",    // Vertical blank immediate vector
            0x0224: "VVBLKD",    // Vertical blank deferred vector

            // CIO entry points
            0xE456: "CIOV",      // Central I/O entry vector

            // SIO entry points
            0xE459: "SIOV",      // Serial I/O entry vector

            // Common OS routines
            0xE400: "EDITRV",    // Editor handler
            0xE410: "SCRENV",    // Screen handler
            0xE420: "KEYBDV",    // Keyboard handler
            0xE430: "PRINTV",    // Printer handler
            0xE440: "CASETV",    // Cassette handler

            // ROM vectors (at end of ROM)
            0xFFFA: "NMI",       // NMI vector
            0xFFFC: "RESET",     // Reset vector
            0xFFFE: "IRQ",       // IRQ vector

            // Other common OS entry points
            0xE462: "SETVBV",    // Set vertical blank vectors
            0xE465: "SYSVBV",    // System VBI
            0xE468: "XITVBV",    // Exit VBI
            0xE46B: "SIOINV",    // SIO initialization
            0xE46E: "SENDEV",    // Send enable
            0xE471: "INTINV",    // Interrupt initialization
            0xE474: "CIOINV",    // CIO initialization
            0xE477: "BLKBDV",    // Blackboard mode
            0xE47A: "WARMSV",    // Warm start entry
            0xE47D: "COLDSV",    // Cold start entry
            0xE480: "RBLOKV",    // Cassette read block
            0xE483: "CSOPIV",    // Cassette open for input
            0xE486: "PUTEFV",    // Put byte to cassette
        ])
    }
}

// =============================================================================
// MARK: - Zero Page Variables ($00-$FF)
// =============================================================================

extension AddressLabels {
    /// Common zero page OS and BASIC variables.
    public static var zeroPageVariables: AddressLabels {
        AddressLabels(labels: [
            // OS zero page
            0x0000: "LINZBS",    // BASIC line number (low)
            0x0001: "LINZBS+1",  // BASIC line number (high)
            0x0002: "CASESSION",  // Cassette session
            0x0003: "CESSION",   // Coldstart session
            0x0004: "WARMST",    // Warmstart flag
            0x0005: "BOOTQ",     // Boot flag
            0x0006: "DOSVEC",    // DOS start vector (low)
            0x0007: "DOSVEC+1",  // DOS start vector (high)
            0x0008: "DOSINI",    // DOS init vector (low)
            0x0009: "DOSINI+1",  // DOS init vector (high)
            0x000A: "APPMHI",    // Application memory high (low)
            0x000B: "APPMHI+1",  // Application memory high (high)

            // POKEY shadow registers
            0x0010: "POKMSK",    // IRQEN shadow
            0x0011: "BRKKEY",    // Break key flag
            0x0012: "RTCLOK",    // Real-time clock (low)
            0x0013: "RTCLOK+1",  // Real-time clock (mid)
            0x0014: "RTCLOK+2",  // Real-time clock (high)

            // Screen/editor variables
            0x0052: "LMARGIN",   // Left margin
            0x0053: "RMARGIN",   // Right margin
            0x0054: "ROWCRS",    // Cursor row
            0x0055: "COLCRS",    // Cursor column (low)
            0x0056: "COLCRS+1",  // Cursor column (high)
            0x0057: "DINDEX",    // Display mode
            0x0058: "SAVMSC",    // Screen memory (low)
            0x0059: "SAVMSC+1",  // Screen memory (high)
            0x005D: "OLDROW",    // Previous cursor row
            0x005E: "OLDCOL",    // Previous cursor column (low)
            0x005F: "OLDCOL+1",  // Previous cursor column (high)
            0x0060: "OLDCHR",    // Character under cursor
            0x0061: "OLDADR",    // Cursor memory address (low)
            0x0062: "OLDADR+1",  // Cursor memory address (high)

            // Color shadows
            0x02C4: "COLOR0",    // COLPF0 shadow
            0x02C5: "COLOR1",    // COLPF1 shadow
            0x02C6: "COLOR2",    // COLPF2 shadow
            0x02C7: "COLOR3",    // COLPF3 shadow
            0x02C8: "COLOR4",    // COLBK shadow

            // ANTIC shadows
            0x0230: "SDLSTL",    // Display list pointer (low) shadow
            0x0231: "SDLSTH",    // Display list pointer (high) shadow
            0x022F: "SDMCTL",    // DMACTL shadow

            // Attract mode
            0x004D: "ATRACT",    // Attract mode timer

            // Character base
            0x02F4: "CHBAS",     // Character base (high byte) shadow

            // BASIC zero page (when BASIC is loaded)
            0x0080: "LOMEM",     // BASIC low memory (low)
            0x0081: "LOMEM+1",   // BASIC low memory (high)
            0x0082: "VNTP",      // Variable name table (low)
            0x0083: "VNTP+1",    // Variable name table (high)
            0x0084: "VNTD",      // Variable name table end (low)
            0x0085: "VNTD+1",    // Variable name table end (high)
            0x0086: "VVTP",      // Variable value table (low)
            0x0087: "VVTP+1",    // Variable value table (high)
            0x0088: "STMTAB",    // Statement table (low)
            0x0089: "STMTAB+1",  // Statement table (high)
            0x008A: "STMCUR",    // Current statement (low)
            0x008B: "STMCUR+1",  // Current statement (high)
            0x008C: "STARP",     // String/array table (low)
            0x008D: "STARP+1",   // String/array table (high)
            0x008E: "RUNSTK",    // Runtime stack (low)
            0x008F: "RUNSTK+1",  // Runtime stack (high)
            0x0090: "MEMTOP",    // BASIC memory top (low)
            0x0091: "MEMTOP+1",  // BASIC memory top (high)

            // Floating point workspace
            0x00D4: "FR0",       // Floating point register 0 (6 bytes)
            0x00E0: "FR1",       // Floating point register 1
            0x00E6: "CIX",       // Input index
            0x00F3: "INBUFF",    // Input buffer pointer (low)
            0x00F4: "INBUFF+1",  // Input buffer pointer (high)
        ])
    }
}

// =============================================================================
// MARK: - Page 2 Variables ($0200-$02FF)
// =============================================================================

extension AddressLabels {
    /// Page 2 OS variables (interrupt vectors and device tables).
    public static var page2Variables: AddressLabels {
        AddressLabels(labels: [
            // Interrupt vectors (see osVectors for $0200-$0224)

            // Device handler table
            0x031A: "HATABS",    // Handler address table

            // Device control blocks (IOCBs)
            // Each IOCB is 16 bytes. The first byte is ICHID (Handler ID).
            // IOCB0 starts at $0340, and also serves as the ICHID0 location.
            0x0340: "IOCB0",     // I/O control block 0 / ICHID0 (Handler ID)
            0x0341: "ICDNO0",    // Device number
            0x0342: "ICCOM0",    // Command
            0x0343: "ICSTA0",    // Status
            0x0344: "ICBAL0",    // Buffer address (low)
            0x0345: "ICBAH0",    // Buffer address (high)
            0x0346: "ICPTL0",    // Put byte routine (low)
            0x0347: "ICPTH0",    // Put byte routine (high)
            0x0348: "ICBLL0",    // Buffer length (low)
            0x0349: "ICBLH0",    // Buffer length (high)
            0x034A: "ICAX10",    // Auxiliary byte 1
            0x034B: "ICAX20",    // Auxiliary byte 2

            0x0350: "IOCB1",     // I/O control block 1
            0x0360: "IOCB2",     // I/O control block 2
            0x0370: "IOCB3",     // I/O control block 3
            0x0380: "IOCB4",     // I/O control block 4
            0x0390: "IOCB5",     // I/O control block 5
            0x03A0: "IOCB6",     // I/O control block 6
            0x03B0: "IOCB7",     // I/O control block 7

            // Printer buffer
            0x03C0: "PRNBUF",    // Printer buffer (40 bytes)

            // Cassette buffer
            0x03FD: "CARONE",    // Cassette record 1
        ])
    }
}

// =============================================================================
// MARK: - Memory Region Labels
// =============================================================================

extension AddressLabels {
    /// Labels for memory region boundaries and important addresses.
    public static var memoryRegions: AddressLabels {
        AddressLabels(labels: [
            0x0000: "ZEROPAGE",  // Zero page start
            0x0100: "STACK",     // Hardware stack
            0x0200: "PAGE2",     // OS variables
            0x0300: "PAGE3",     // Device handler area
            0x0400: "PAGE4",     // Usually free
            0x0500: "PAGE5",     // Usually free
            0x0600: "USER",      // User RAM start (typical)

            0xA000: "BASICROM",  // BASIC ROM start
            0xC000: "OSRAM",     // OS RAM / Self-test ROM
            0xD000: "HARDWARE",  // Hardware registers start
            0xD800: "FLOATROM",  // Floating point ROM
            0xE000: "OSROM",     // OS ROM start
        ])
    }
}
