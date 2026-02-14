package atticprotocol

import (
	"fmt"
	"strings"
)

// ResponseType represents the type of response from the server.
type ResponseType int

const (
	// ResponseOK indicates a successful response.
	ResponseOK ResponseType = iota
	// ResponseError indicates an error response.
	ResponseError
)

// Response represents a response to a CLI command.
type Response struct {
	Type ResponseType
	Data string // The response data (for OK) or error message (for Error)
}

// NewOKResponse creates a successful response with the given data.
func NewOKResponse(data string) Response {
	return Response{Type: ResponseOK, Data: data}
}

// NewErrorResponse creates an error response with the given message.
func NewErrorResponse(message string) Response {
	return Response{Type: ResponseError, Data: message}
}

// NewMultiLineResponse creates a successful response from multiple lines.
// Lines are joined using the MultiLineSeparator character.
func NewMultiLineResponse(lines []string) Response {
	return Response{
		Type: ResponseOK,
		Data: strings.Join(lines, MultiLineSeparator),
	}
}

// IsOK returns true if this is a successful response.
func (r Response) IsOK() bool {
	return r.Type == ResponseOK
}

// IsError returns true if this is an error response.
func (r Response) IsError() bool {
	return r.Type == ResponseError
}

// Format returns the response formatted for transmission over the protocol.
func (r Response) Format() string {
	switch r.Type {
	case ResponseOK:
		return OKPrefix + r.Data
	case ResponseError:
		return ErrorPrefix + r.Data
	default:
		return ErrorPrefix + "unknown response type"
	}
}

// Lines returns the response data split by the multi-line separator.
// Useful for processing multi-line responses like disassembly output.
func (r Response) Lines() []string {
	if r.Data == "" {
		return nil
	}
	return strings.Split(r.Data, MultiLineSeparator)
}

// EventType represents the type of async event from the server.
type EventType int

const (
	// EventBreakpoint indicates a breakpoint was hit.
	EventBreakpoint EventType = iota
	// EventStopped indicates the emulator stopped (e.g., BRK without breakpoint).
	EventStopped
	// EventError indicates an async error occurred.
	EventError
)

// Event represents an asynchronous event from the server.
type Event struct {
	Type EventType

	// For EventBreakpoint
	Address uint16
	A, X, Y uint8 // Register values
	S, P    uint8 // Stack pointer and processor status

	// For EventError
	Message string
}

// NewBreakpointEvent creates a breakpoint event with register state.
func NewBreakpointEvent(address uint16, a, x, y, s, p uint8) Event {
	return Event{
		Type:    EventBreakpoint,
		Address: address,
		A:       a,
		X:       x,
		Y:       y,
		S:       s,
		P:       p,
	}
}

// NewStoppedEvent creates a stopped event at the given address.
func NewStoppedEvent(address uint16) Event {
	return Event{
		Type:    EventStopped,
		Address: address,
	}
}

// NewErrorEvent creates an error event with the given message.
func NewErrorEvent(message string) Event {
	return Event{
		Type:    EventError,
		Message: message,
	}
}

// Format returns the event formatted for transmission over the protocol.
func (e Event) Format() string {
	switch e.Type {
	case EventBreakpoint:
		return fmt.Sprintf("%sbreakpoint $%04X A=$%02X X=$%02X Y=$%02X S=$%02X P=$%02X",
			EventPrefix, e.Address, e.A, e.X, e.Y, e.S, e.P)
	case EventStopped:
		return fmt.Sprintf("%sstopped $%04X", EventPrefix, e.Address)
	case EventError:
		return fmt.Sprintf("%serror %s", EventPrefix, e.Message)
	default:
		return fmt.Sprintf("%serror unknown event type", EventPrefix)
	}
}
