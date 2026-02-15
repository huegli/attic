// =============================================================================
// repl.go - REPL Loop (Stub for Phase 1)
// =============================================================================
//
// This file will contain the full REPL implementation in Phase 4. For now it
// provides a minimal stub that reads lines from stdin and sends them as raw
// protocol commands, so the CLI can be tested end-to-end.
//
// =============================================================================

package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"github.com/attic/atticprotocol"
)

// REPLMode represents the current operating mode of the REPL.
type REPLMode int

const (
	// ModeMonitor is the 6502 debugging mode.
	ModeMonitor REPLMode = iota
	// ModeBasic is the BASIC programming mode.
	ModeBasic
	// ModeDOS is the disk management mode.
	ModeDOS
)

// prompt returns the display prompt for the current REPL mode.
func (m REPLMode) prompt() string {
	switch m {
	case ModeMonitor:
		return "[monitor] > "
	case ModeBasic:
		return "[basic] > "
	case ModeDOS:
		return "[dos] D1:> "
	default:
		return "> "
	}
}

// runREPL runs the main REPL loop.
//
// This is a minimal stub for Phase 1. It reads lines from stdin and sends
// them as raw protocol commands. The full implementation with command
// translation, mode switching, help system, and line editing will be added
// in subsequent phases.
func runREPL(client *atticprotocol.Client, atasciiMode bool) {
	scanner := bufio.NewScanner(os.Stdin)
	mode := ModeBasic

	for {
		// Print prompt
		fmt.Print(mode.prompt())

		// Read a line
		if !scanner.Scan() {
			// EOF (Ctrl-D) or error
			fmt.Println()
			return
		}

		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}

		// Handle local dot-commands
		switch line {
		case ".quit":
			return
		case ".monitor":
			mode = ModeMonitor
			fmt.Println("Switched to Monitor mode")
			continue
		case ".basic":
			mode = ModeBasic
			fmt.Println("Switched to BASIC mode")
			continue
		case ".dos":
			mode = ModeDOS
			fmt.Println("Switched to DOS mode")
			continue
		case ".help":
			fmt.Println("Help system will be implemented in Phase 6.")
			fmt.Println("Dot-commands: .monitor .basic .dos .quit .help")
			continue
		}

		// Send as raw protocol command (no translation yet)
		resp, err := client.SendRaw(line)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			continue
		}

		// Display response, expanding multi-line separators
		if resp.IsOK() {
			if resp.Data != "" {
				output := strings.ReplaceAll(resp.Data, atticprotocol.MultiLineSeparator, "\n")
				fmt.Println(output)
			}
		} else {
			fmt.Fprintf(os.Stderr, "Error: %s\n", resp.Data)
		}
	}
}
