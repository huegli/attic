// Package atticprotocol implements the CLI text-based protocol for
// communication between CLI clients and the AtticServer emulator.
//
// This is the Go implementation of the protocol defined in the Swift
// AtticCore module. It is designed to be protocol-compatible while
// following Go idioms and best practices.
//
// Protocol Format:
//
//	Request (CLI -> Server):   CMD:<command> [arguments...]\n
//	Success Response:          OK:<response-data>\n
//	Error Response:            ERR:<error-message>\n
//	Async Event:               EVENT:<event-type> <data>\n
//	Multi-line Separator:      \x1E (Record Separator)
//
// Example Session:
//
//	CLI: CMD:ping
//	SRV: OK:pong
//	CLI: CMD:pause
//	SRV: OK:paused
//	CLI: CMD:read $0600 16
//	SRV: OK:data A9,00,8D,00,D4,A9,01,8D,01,D4,60,00,00,00,00,00
package atticprotocol

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"time"
)

// Protocol constants matching the Swift implementation.
const (
	// CommandPrefix is the prefix for commands sent from CLI to Server.
	CommandPrefix = "CMD:"

	// OKPrefix is the prefix for success responses from Server to CLI.
	OKPrefix = "OK:"

	// ErrorPrefix is the prefix for error responses from Server to CLI.
	ErrorPrefix = "ERR:"

	// EventPrefix is the prefix for async events from Server to CLI.
	EventPrefix = "EVENT:"

	// MultiLineSeparator is the character used to separate multiple lines
	// in a single response (Record Separator character, ASCII 0x1E).
	MultiLineSeparator = "\x1E"

	// SocketPathPrefix is the prefix for server socket paths.
	SocketPathPrefix = "/tmp/attic-"

	// SocketPathSuffix is the suffix for server socket paths.
	SocketPathSuffix = ".sock"

	// MaxLineLength is the maximum allowed length for a protocol line in bytes.
	MaxLineLength = 4096

	// CommandTimeout is the default timeout for commands.
	CommandTimeout = 30 * time.Second

	// PingTimeout is the timeout used for ping commands during connection verification.
	PingTimeout = 1 * time.Second

	// ConnectionTimeout is the timeout for establishing connections.
	ConnectionTimeout = 5 * time.Second

	// ProtocolVersion is the version string for the CLI protocol.
	ProtocolVersion = "1.0"
)

// SocketPath returns the socket path for a given process ID.
func SocketPath(pid int) string {
	return fmt.Sprintf("%s%d%s", SocketPathPrefix, pid, SocketPathSuffix)
}

// CurrentSocketPath returns the socket path for the current process.
func CurrentSocketPath() string {
	return SocketPath(os.Getpid())
}

// DiscoverSockets finds all AtticServer sockets in /tmp.
// Returns socket paths sorted by modification time (most recent first).
func DiscoverSockets() ([]string, error) {
	pattern := filepath.Join("/tmp", "attic-*.sock")
	matches, err := filepath.Glob(pattern)
	if err != nil {
		return nil, fmt.Errorf("failed to glob sockets: %w", err)
	}

	// Get modification times and sort
	type socketInfo struct {
		path    string
		modTime time.Time
	}
	sockets := make([]socketInfo, 0, len(matches))

	for _, path := range matches {
		info, err := os.Stat(path)
		if err != nil {
			continue // Skip inaccessible sockets
		}
		sockets = append(sockets, socketInfo{
			path:    path,
			modTime: info.ModTime(),
		})
	}

	// Sort by modification time (most recent first)
	sort.Slice(sockets, func(i, j int) bool {
		return sockets[i].modTime.After(sockets[j].modTime)
	})

	result := make([]string, len(sockets))
	for i, s := range sockets {
		result[i] = s.path
	}

	return result, nil
}

// DiscoverSocket finds the most recently active AtticServer socket.
// Returns empty string if no socket is found.
func DiscoverSocket() string {
	sockets, err := DiscoverSockets()
	if err != nil || len(sockets) == 0 {
		return ""
	}
	return sockets[0]
}
