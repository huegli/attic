// Package atticprotocol provides a Go implementation of the CLI text-based
// protocol for communication with the AtticServer Atari 800 XL emulator.
//
// This package is a Go port of the Swift CLIProtocol and CLISocketClient
// from the AtticCore module, designed to be protocol-compatible while
// following Go idioms and best practices.
//
// # Protocol Overview
//
// The CLI protocol is a simple text-based, line-oriented protocol designed
// for REPL-style interaction. It uses Unix domain sockets for communication.
//
//	Request format:   CMD:<command> [arguments...]\n
//	Success response: OK:<response-data>\n
//	Error response:   ERR:<error-message>\n
//	Async event:      EVENT:<event-type> <data>\n
//
// Multi-line responses use the Record Separator character (0x1E) to delimit
// lines within a single response.
//
// # Basic Usage
//
// Create a client and connect to a running AtticServer:
//
//	client := atticprotocol.NewClient()
//
//	// Auto-discover and connect to a running server
//	if err := client.DiscoverAndConnect(); err != nil {
//	    log.Fatal(err)
//	}
//	defer client.Disconnect()
//
//	// Send commands
//	resp, err := client.Send(atticprotocol.NewPauseCommand())
//	if err != nil {
//	    log.Fatal(err)
//	}
//	if resp.IsOK() {
//	    fmt.Println("Emulator paused")
//	}
//
// # Event Handling
//
// To receive async events like breakpoint notifications:
//
//	client.SetEventHandler(func(event atticprotocol.Event) {
//	    switch event.Type {
//	    case atticprotocol.EventBreakpoint:
//	        fmt.Printf("Breakpoint hit at $%04X\n", event.Address)
//	    case atticprotocol.EventStopped:
//	        fmt.Printf("Emulator stopped at $%04X\n", event.Address)
//	    case atticprotocol.EventError:
//	        fmt.Printf("Error: %s\n", event.Message)
//	    }
//	})
//
// # Command Types
//
// The package provides constructor functions for all supported commands:
//
//   - Connection: NewPingCommand, NewVersionCommand, NewQuitCommand, NewShutdownCommand
//   - Emulator: NewPauseCommand, NewResumeCommand, NewStepCommand, NewResetCommand, NewStatusCommand
//   - Memory: NewReadCommand, NewWriteCommand, NewRegistersCommand
//   - Breakpoints: NewBreakpointSetCommand, NewBreakpointClearCommand, NewBreakpointClearAllCommand, NewBreakpointListCommand
//   - Assembly: NewAssembleCommand, NewAssembleLineCommand, NewDisassembleCommand
//   - Monitor: NewStepOverCommand, NewRunUntilCommand, NewMemoryFillCommand
//   - Disk: NewMountCommand, NewUnmountCommand, NewDrivesCommand
//   - Boot: NewBootCommand
//   - State: NewStateSaveCommand, NewStateLoadCommand
//   - Display: NewScreenshotCommand
//   - Injection: NewInjectBasicCommand, NewInjectKeysCommand
//   - BASIC: NewBasicLineCommand, NewBasicNewCommand, NewBasicRunCommand, NewBasicListCommand
//   - BASIC Editing: NewBasicDeleteCommand, NewBasicStopCommand, NewBasicContCommand, NewBasicVarsCommand, NewBasicVarCommand, NewBasicInfoCommand, NewBasicExportCommand, NewBasicImportCommand, NewBasicDirCommand
//
// # Parsing Commands
//
// To parse command text (e.g., from user input):
//
//	parser := atticprotocol.NewCommandParser()
//	cmd, err := parser.Parse("read $0600 16")
//	if err != nil {
//	    log.Fatal(err)
//	}
//
// # Thread Safety
//
// The Client type is safe for concurrent use from multiple goroutines.
// All public methods use proper synchronization.
package atticprotocol
