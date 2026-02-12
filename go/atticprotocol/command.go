package atticprotocol

import (
	"fmt"
	"strings"
)

// CommandType represents the type of CLI command.
type CommandType int

const (
	// Connection commands
	CmdPing CommandType = iota
	CmdVersion
	CmdQuit
	CmdShutdown

	// Emulator control
	CmdPause
	CmdResume
	CmdStep
	CmdReset
	CmdStatus

	// Memory operations
	CmdRead
	CmdWrite
	CmdRegisters

	// Breakpoints
	CmdBreakpointSet
	CmdBreakpointClear
	CmdBreakpointClearAll
	CmdBreakpointList

	// Assembly
	CmdAssemble
	CmdAssembleLine
	CmdDisassemble

	// Monitor
	CmdStepOver
	CmdRunUntil
	CmdMemoryFill

	// Disk operations
	CmdMount
	CmdUnmount
	CmdDrives

	// Boot with file
	CmdBoot

	// State management
	CmdStateSave
	CmdStateLoad

	// Display
	CmdScreenshot

	// Injection
	CmdInjectBasic
	CmdInjectKeys

	// BASIC commands
	CmdBasicLine
	CmdBasicNew
	CmdBasicRun
	CmdBasicList

	// BASIC editing commands
	CmdBasicDelete
	CmdBasicStop
	CmdBasicCont
	CmdBasicVars
	CmdBasicVar
	CmdBasicInfo
	CmdBasicExport
	CmdBasicImport
	CmdBasicDir
)

// RegisterModification represents a register name and value pair for modification.
type RegisterModification struct {
	Name  string // A, X, Y, S, P, or PC
	Value uint16
}

// Command represents a parsed CLI command with its arguments.
// Use the constructor functions (NewPingCommand, NewReadCommand, etc.)
// to create Command instances.
type Command struct {
	Type CommandType

	// Fields used by various commands (only relevant fields are populated)
	Count         int                    // For step, read, disassemble
	Cold          bool                   // For reset
	Address       uint16                 // For read, write, breakpoints, assemble, etc.
	AddressSet    bool                   // Whether Address was explicitly provided
	EndAddress    uint16                 // For memoryFill
	Data          []byte                 // For write
	Modifications []RegisterModification // For registers
	Drive         int                    // For mount, unmount
	Path          string                 // For mount, state operations, screenshot
	Base64Data    string                 // For injectBasic
	Text          string                 // For injectKeys
	Instruction   string                 // For assembleLine
	Line          string                 // For basicLine
	Value         byte                   // For memoryFill
	Lines         int                    // For disassemble
	LinesSet      bool                   // Whether Lines was explicitly provided
	LineOrRange   string                 // For basicDelete (e.g., "10" or "10-50")
	VarName       string                 // For basicVar
}

// Command constructors - these provide a clean API for creating commands.

// NewPingCommand creates a ping command.
func NewPingCommand() Command {
	return Command{Type: CmdPing}
}

// NewVersionCommand creates a version command.
func NewVersionCommand() Command {
	return Command{Type: CmdVersion}
}

// NewQuitCommand creates a quit command.
func NewQuitCommand() Command {
	return Command{Type: CmdQuit}
}

// NewShutdownCommand creates a shutdown command.
func NewShutdownCommand() Command {
	return Command{Type: CmdShutdown}
}

// NewPauseCommand creates a pause command.
func NewPauseCommand() Command {
	return Command{Type: CmdPause}
}

// NewResumeCommand creates a resume command.
func NewResumeCommand() Command {
	return Command{Type: CmdResume}
}

// NewStepCommand creates a step command with the given count.
// If count is 0 or 1, a single step is performed.
func NewStepCommand(count int) Command {
	if count <= 0 {
		count = 1
	}
	return Command{Type: CmdStep, Count: count}
}

// NewResetCommand creates a reset command.
// If cold is true, performs a cold reset; otherwise, a warm reset.
func NewResetCommand(cold bool) Command {
	return Command{Type: CmdReset, Cold: cold}
}

// NewStatusCommand creates a status command.
func NewStatusCommand() Command {
	return Command{Type: CmdStatus}
}

// NewReadCommand creates a read command for the given address and byte count.
func NewReadCommand(address, count uint16) Command {
	return Command{Type: CmdRead, Address: address, AddressSet: true, Count: int(count)}
}

// NewWriteCommand creates a write command for the given address and data.
func NewWriteCommand(address uint16, data []byte) Command {
	return Command{Type: CmdWrite, Address: address, AddressSet: true, Data: data}
}

// NewRegistersCommand creates a registers command.
// If modifications is nil, returns current register values.
// Otherwise, applies the specified modifications.
func NewRegistersCommand(modifications []RegisterModification) Command {
	return Command{Type: CmdRegisters, Modifications: modifications}
}

// NewBreakpointSetCommand creates a command to set a breakpoint at the given address.
func NewBreakpointSetCommand(address uint16) Command {
	return Command{Type: CmdBreakpointSet, Address: address, AddressSet: true}
}

// NewBreakpointClearCommand creates a command to clear a breakpoint at the given address.
func NewBreakpointClearCommand(address uint16) Command {
	return Command{Type: CmdBreakpointClear, Address: address, AddressSet: true}
}

// NewBreakpointClearAllCommand creates a command to clear all breakpoints.
func NewBreakpointClearAllCommand() Command {
	return Command{Type: CmdBreakpointClearAll}
}

// NewBreakpointListCommand creates a command to list all breakpoints.
func NewBreakpointListCommand() Command {
	return Command{Type: CmdBreakpointList}
}

// NewAssembleCommand creates an assemble command for interactive assembly mode.
func NewAssembleCommand(address uint16) Command {
	return Command{Type: CmdAssemble, Address: address, AddressSet: true}
}

// NewAssembleLineCommand creates a command to assemble a single instruction.
func NewAssembleLineCommand(address uint16, instruction string) Command {
	return Command{Type: CmdAssembleLine, Address: address, AddressSet: true, Instruction: instruction}
}

// NewDisassembleCommand creates a disassemble command.
// If address is nil, disassembles from current PC.
// If lines is nil, defaults to 16 lines.
func NewDisassembleCommand(address *uint16, lines *int) Command {
	cmd := Command{Type: CmdDisassemble}
	if address != nil {
		cmd.Address = *address
		cmd.AddressSet = true
	}
	if lines != nil {
		cmd.Lines = *lines
		cmd.LinesSet = true
	}
	return cmd
}

// NewStepOverCommand creates a step-over command.
func NewStepOverCommand() Command {
	return Command{Type: CmdStepOver}
}

// NewRunUntilCommand creates a run-until command for the given address.
func NewRunUntilCommand(address uint16) Command {
	return Command{Type: CmdRunUntil, Address: address, AddressSet: true}
}

// NewMemoryFillCommand creates a command to fill memory with a value.
func NewMemoryFillCommand(start, end uint16, value byte) Command {
	return Command{Type: CmdMemoryFill, Address: start, AddressSet: true, EndAddress: end, Value: value}
}

// NewMountCommand creates a command to mount a disk image.
func NewMountCommand(drive int, path string) Command {
	return Command{Type: CmdMount, Drive: drive, Path: path}
}

// NewUnmountCommand creates a command to unmount a drive.
func NewUnmountCommand(drive int) Command {
	return Command{Type: CmdUnmount, Drive: drive}
}

// NewDrivesCommand creates a command to list mounted drives.
func NewDrivesCommand() Command {
	return Command{Type: CmdDrives}
}

// NewBootCommand creates a command to boot the emulator with a file.
// Supports ATR, XEX, BAS, LST, CAS, ROM, etc.
func NewBootCommand(path string) Command {
	return Command{Type: CmdBoot, Path: path}
}

// NewStateSaveCommand creates a command to save emulator state.
func NewStateSaveCommand(path string) Command {
	return Command{Type: CmdStateSave, Path: path}
}

// NewStateLoadCommand creates a command to load emulator state.
func NewStateLoadCommand(path string) Command {
	return Command{Type: CmdStateLoad, Path: path}
}

// NewScreenshotCommand creates a command to take a screenshot.
// If path is empty, a default path is used.
func NewScreenshotCommand(path string) Command {
	return Command{Type: CmdScreenshot, Path: path}
}

// NewInjectBasicCommand creates a command to inject BASIC data.
func NewInjectBasicCommand(base64Data string) Command {
	return Command{Type: CmdInjectBasic, Base64Data: base64Data}
}

// NewInjectKeysCommand creates a command to inject keystrokes.
func NewInjectKeysCommand(text string) Command {
	return Command{Type: CmdInjectKeys, Text: text}
}

// NewBasicLineCommand creates a command to enter a BASIC line.
func NewBasicLineCommand(line string) Command {
	return Command{Type: CmdBasicLine, Line: line}
}

// NewBasicNewCommand creates a BASIC NEW command.
func NewBasicNewCommand() Command {
	return Command{Type: CmdBasicNew}
}

// NewBasicRunCommand creates a BASIC RUN command.
func NewBasicRunCommand() Command {
	return Command{Type: CmdBasicRun}
}

// NewBasicListCommand creates a BASIC LIST command.
func NewBasicListCommand() Command {
	return Command{Type: CmdBasicList}
}

// NewBasicDeleteCommand creates a command to delete a BASIC line or range.
// lineOrRange can be a single line number (e.g., "10") or a range (e.g., "10-50").
func NewBasicDeleteCommand(lineOrRange string) Command {
	return Command{Type: CmdBasicDelete, LineOrRange: lineOrRange}
}

// NewBasicStopCommand creates a command to stop a running BASIC program.
func NewBasicStopCommand() Command {
	return Command{Type: CmdBasicStop}
}

// NewBasicContCommand creates a command to continue a stopped BASIC program.
func NewBasicContCommand() Command {
	return Command{Type: CmdBasicCont}
}

// NewBasicVarsCommand creates a command to list all BASIC variables.
func NewBasicVarsCommand() Command {
	return Command{Type: CmdBasicVars}
}

// NewBasicVarCommand creates a command to show a specific BASIC variable.
func NewBasicVarCommand(name string) Command {
	return Command{Type: CmdBasicVar, VarName: name}
}

// NewBasicInfoCommand creates a command to show BASIC program information.
func NewBasicInfoCommand() Command {
	return Command{Type: CmdBasicInfo}
}

// NewBasicExportCommand creates a command to export a BASIC program to a file.
func NewBasicExportCommand(path string) Command {
	return Command{Type: CmdBasicExport, Path: path}
}

// NewBasicImportCommand creates a command to import a BASIC program from a file.
func NewBasicImportCommand(path string) Command {
	return Command{Type: CmdBasicImport, Path: path}
}

// NewBasicDirCommand creates a command to list files on a disk drive.
// If drive is nil, uses the default drive.
func NewBasicDirCommand(drive *int) Command {
	cmd := Command{Type: CmdBasicDir}
	if drive != nil {
		cmd.Drive = *drive
		cmd.AddressSet = true // Reuse AddressSet to indicate drive was set
	}
	return cmd
}

// Format returns the command formatted for transmission over the protocol.
// This does not include the CMD: prefix or trailing newline.
func (c Command) Format() string {
	switch c.Type {
	case CmdPing:
		return "ping"
	case CmdVersion:
		return "version"
	case CmdQuit:
		return "quit"
	case CmdShutdown:
		return "shutdown"
	case CmdPause:
		return "pause"
	case CmdResume:
		return "resume"
	case CmdStep:
		if c.Count <= 1 {
			return "step"
		}
		return fmt.Sprintf("step %d", c.Count)
	case CmdReset:
		if c.Cold {
			return "reset cold"
		}
		return "reset warm"
	case CmdStatus:
		return "status"
	case CmdRead:
		return fmt.Sprintf("read $%04X %d", c.Address, c.Count)
	case CmdWrite:
		hexBytes := make([]string, len(c.Data))
		for i, b := range c.Data {
			hexBytes[i] = fmt.Sprintf("%02X", b)
		}
		return fmt.Sprintf("write $%04X %s", c.Address, strings.Join(hexBytes, ","))
	case CmdRegisters:
		if c.Modifications == nil || len(c.Modifications) == 0 {
			return "registers"
		}
		mods := make([]string, len(c.Modifications))
		for i, m := range c.Modifications {
			mods[i] = fmt.Sprintf("%s=$%04X", m.Name, m.Value)
		}
		return "registers " + strings.Join(mods, " ")
	case CmdBreakpointSet:
		return fmt.Sprintf("breakpoint set $%04X", c.Address)
	case CmdBreakpointClear:
		return fmt.Sprintf("breakpoint clear $%04X", c.Address)
	case CmdBreakpointClearAll:
		return "breakpoint clearall"
	case CmdBreakpointList:
		return "breakpoint list"
	case CmdAssemble:
		return fmt.Sprintf("assemble $%04X", c.Address)
	case CmdAssembleLine:
		return fmt.Sprintf("assemble $%04X %s", c.Address, c.Instruction)
	case CmdDisassemble:
		cmd := "disassemble"
		if c.AddressSet {
			cmd += fmt.Sprintf(" $%04X", c.Address)
		}
		if c.LinesSet {
			if !c.AddressSet {
				cmd += " ."
			}
			cmd += fmt.Sprintf(" %d", c.Lines)
		}
		return cmd
	case CmdStepOver:
		return "stepover"
	case CmdRunUntil:
		return fmt.Sprintf("until $%04X", c.Address)
	case CmdMemoryFill:
		return fmt.Sprintf("fill $%04X $%04X $%02X", c.Address, c.EndAddress, c.Value)
	case CmdMount:
		return fmt.Sprintf("mount %d %s", c.Drive, c.Path)
	case CmdUnmount:
		return fmt.Sprintf("unmount %d", c.Drive)
	case CmdDrives:
		return "drives"
	case CmdBoot:
		return fmt.Sprintf("boot %s", c.Path)
	case CmdStateSave:
		return fmt.Sprintf("state save %s", c.Path)
	case CmdStateLoad:
		return fmt.Sprintf("state load %s", c.Path)
	case CmdScreenshot:
		if c.Path == "" {
			return "screenshot"
		}
		return fmt.Sprintf("screenshot %s", c.Path)
	case CmdInjectBasic:
		return fmt.Sprintf("inject basic %s", c.Base64Data)
	case CmdInjectKeys:
		// Escape special characters (including space to prevent parser issues)
		escaped := c.Text
		escaped = strings.ReplaceAll(escaped, "\\", "\\\\")
		escaped = strings.ReplaceAll(escaped, "\n", "\\n")
		escaped = strings.ReplaceAll(escaped, "\t", "\\t")
		escaped = strings.ReplaceAll(escaped, "\r", "\\r")
		escaped = strings.ReplaceAll(escaped, " ", "\\s")
		return fmt.Sprintf("inject keys %s", escaped)
	case CmdBasicLine:
		return fmt.Sprintf("basic %s", c.Line)
	case CmdBasicNew:
		return "basic NEW"
	case CmdBasicRun:
		return "basic RUN"
	case CmdBasicList:
		return "basic LIST"
	case CmdBasicDelete:
		return fmt.Sprintf("basic DEL %s", c.LineOrRange)
	case CmdBasicStop:
		return "basic STOP"
	case CmdBasicCont:
		return "basic CONT"
	case CmdBasicVars:
		return "basic VARS"
	case CmdBasicVar:
		return fmt.Sprintf("basic VAR %s", c.VarName)
	case CmdBasicInfo:
		return "basic INFO"
	case CmdBasicExport:
		return fmt.Sprintf("basic EXPORT %s", c.Path)
	case CmdBasicImport:
		return fmt.Sprintf("basic IMPORT %s", c.Path)
	case CmdBasicDir:
		if c.AddressSet { // AddressSet is reused to indicate drive was set
			return fmt.Sprintf("basic DIR %d", c.Drive)
		}
		return "basic DIR"
	default:
		return ""
	}
}

// FormatWithPrefix returns the command formatted for transmission with the CMD: prefix.
func (c Command) FormatWithPrefix() string {
	return CommandPrefix + c.Format()
}

// FormatLine returns the command formatted as a complete protocol line with newline.
func (c Command) FormatLine() string {
	return c.FormatWithPrefix() + "\n"
}
