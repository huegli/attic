package atticprotocol

import (
	"bufio"
	"context"
	"fmt"
	"net"
	"sync"
	"sync/atomic"
	"time"
)

// EventHandler is a callback function for handling async events from the server.
type EventHandler func(event Event)

// DisconnectHandler is a callback function called when the connection is lost.
type DisconnectHandler func(err error)

// Client is a Unix domain socket client for connecting to AtticServer.
//
// It implements the CLI text protocol for sending commands to the emulator
// server and receiving responses. It also handles async events like
// breakpoint notifications.
//
// Thread Safety:
// The client uses a mutex to protect its state and is safe for concurrent
// use from multiple goroutines.
type Client struct {
	mu sync.Mutex

	conn          net.Conn
	connectedPath string
	isConnected   bool

	reader *bufio.Reader

	// Response channel for pending requests
	pendingResponse chan responseResult
	requestID       atomic.Uint64

	// Handlers for async events
	eventHandler      EventHandler
	disconnectHandler DisconnectHandler

	// Parsers
	responseParser *ResponseParser

	// Cancellation for the reader goroutine
	cancelReader context.CancelFunc
	readerDone   chan struct{}
}

// responseResult wraps a response or error from the server.
type responseResult struct {
	response Response
	err      error
}

// NewClient creates a new CLI socket client.
func NewClient() *Client {
	return &Client{
		responseParser: NewResponseParser(),
	}
}

// SetEventHandler sets the callback for async events from the server.
func (c *Client) SetEventHandler(handler EventHandler) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.eventHandler = handler
}

// SetDisconnectHandler sets the callback for disconnection events.
func (c *Client) SetDisconnectHandler(handler DisconnectHandler) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.disconnectHandler = handler
}

// IsConnected returns true if the client is currently connected.
func (c *Client) IsConnected() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.isConnected
}

// ConnectedPath returns the path of the currently connected socket.
// Returns empty string if not connected.
func (c *Client) ConnectedPath() string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.connectedPath
}

// Connect connects to an AtticServer socket.
func (c *Client) Connect(path string) error {
	return c.ConnectWithContext(context.Background(), path)
}

// ConnectWithContext connects to an AtticServer socket with a context for cancellation.
func (c *Client) ConnectWithContext(ctx context.Context, path string) error {
	c.mu.Lock()
	if c.isConnected {
		c.mu.Unlock()
		return ErrAlreadyConnected
	}
	c.mu.Unlock()

	// Create a context with timeout for the connection
	connectCtx, cancel := context.WithTimeout(ctx, ConnectionTimeout)
	defer cancel()

	// Dial the Unix socket
	var d net.Dialer
	conn, err := d.DialContext(connectCtx, "unix", path)
	if err != nil {
		return NewConnectionError("failed to connect", err)
	}

	c.mu.Lock()
	c.conn = conn
	c.connectedPath = path
	c.isConnected = true
	c.reader = bufio.NewReader(conn)
	c.pendingResponse = make(chan responseResult, 1)

	// Create cancellation context for reader
	readerCtx, cancelReader := context.WithCancel(context.Background())
	c.cancelReader = cancelReader
	c.readerDone = make(chan struct{})

	// Start reader goroutine
	go c.readerLoop(readerCtx)
	c.mu.Unlock()

	// Verify connection with ping
	pingCtx, pingCancel := context.WithTimeout(ctx, PingTimeout)
	defer pingCancel()

	resp, err := c.SendWithContext(pingCtx, NewPingCommand())
	if err != nil {
		c.Disconnect()
		return NewConnectionError("ping failed", err)
	}
	if !resp.IsOK() || resp.Data != "pong" {
		c.Disconnect()
		return NewConnectionError("server ping failed", nil)
	}

	return nil
}

// Disconnect disconnects from the server.
func (c *Client) Disconnect() {
	c.mu.Lock()
	if !c.isConnected {
		c.mu.Unlock()
		return
	}

	c.isConnected = false

	// Cancel reader goroutine
	if c.cancelReader != nil {
		c.cancelReader()
	}
	c.mu.Unlock()

	// Wait for reader to finish (outside lock to avoid deadlock)
	if c.readerDone != nil {
		<-c.readerDone
	}

	c.mu.Lock()
	// Close connection
	if c.conn != nil {
		c.conn.Close()
		c.conn = nil
	}

	// Clear pending response
	if c.pendingResponse != nil {
		// Non-blocking drain
		select {
		case <-c.pendingResponse:
		default:
		}
		close(c.pendingResponse)
		c.pendingResponse = nil
	}

	c.connectedPath = ""
	c.reader = nil
	c.cancelReader = nil
	c.readerDone = nil
	c.mu.Unlock()
}

// Send sends a command to the server and waits for a response.
// Uses the default CommandTimeout.
func (c *Client) Send(cmd Command) (Response, error) {
	return c.SendWithTimeout(cmd, CommandTimeout)
}

// SendWithTimeout sends a command with a custom timeout.
func (c *Client) SendWithTimeout(cmd Command, timeout time.Duration) (Response, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	return c.SendWithContext(ctx, cmd)
}

// SendWithContext sends a command with a context for cancellation/timeout.
func (c *Client) SendWithContext(ctx context.Context, cmd Command) (Response, error) {
	c.mu.Lock()
	if !c.isConnected {
		c.mu.Unlock()
		return Response{}, ErrNotConnected
	}

	conn := c.conn
	pendingChan := c.pendingResponse
	c.mu.Unlock()

	// Format and send command
	line := cmd.FormatLine()
	_, err := conn.Write([]byte(line))
	if err != nil {
		return Response{}, NewConnectionError("failed to send command", err)
	}

	// Wait for response or timeout
	select {
	case result := <-pendingChan:
		return result.response, result.err
	case <-ctx.Done():
		return Response{}, ErrTimeout
	}
}

// SendRaw sends a raw command string to the server.
// The command should not include the CMD: prefix or trailing newline.
func (c *Client) SendRaw(commandLine string) (Response, error) {
	return c.SendRawWithTimeout(commandLine, CommandTimeout)
}

// SendRawWithTimeout sends a raw command string with a custom timeout.
func (c *Client) SendRawWithTimeout(commandLine string, timeout time.Duration) (Response, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	return c.SendRawWithContext(ctx, commandLine)
}

// SendRawWithContext sends a raw command string with a context.
func (c *Client) SendRawWithContext(ctx context.Context, commandLine string) (Response, error) {
	c.mu.Lock()
	if !c.isConnected {
		c.mu.Unlock()
		return Response{}, ErrNotConnected
	}

	conn := c.conn
	pendingChan := c.pendingResponse
	c.mu.Unlock()

	// Format and send command
	line := fmt.Sprintf("%s%s\n", CommandPrefix, commandLine)
	_, err := conn.Write([]byte(line))
	if err != nil {
		return Response{}, NewConnectionError("failed to send command", err)
	}

	// Wait for response or timeout
	select {
	case result := <-pendingChan:
		return result.response, result.err
	case <-ctx.Done():
		return Response{}, ErrTimeout
	}
}

// readerLoop continuously reads from the socket and dispatches responses/events.
func (c *Client) readerLoop(ctx context.Context) {
	defer func() {
		c.mu.Lock()
		if c.readerDone != nil {
			close(c.readerDone)
		}
		c.mu.Unlock()
	}()

	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		// Set read deadline to allow checking for cancellation
		c.mu.Lock()
		if c.conn == nil {
			c.mu.Unlock()
			return
		}
		c.conn.SetReadDeadline(time.Now().Add(100 * time.Millisecond))
		reader := c.reader
		c.mu.Unlock()

		line, err := reader.ReadString('\n')
		if err != nil {
			// Check if it's a timeout (expected for responsive cancellation)
			if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
				continue
			}

			// Real error - handle disconnect
			c.handleDisconnect(err)
			return
		}

		c.processLine(line)
	}
}

// processLine handles a received line from the server.
func (c *Client) processLine(line string) {
	parsed, err := c.responseParser.Parse(line)
	if err != nil {
		// Log parse error but don't fail
		fmt.Printf("[CLIClient] Failed to parse response: %v\n", err)
		return
	}

	if parsed.IsEvent {
		// Dispatch event to handler
		c.mu.Lock()
		handler := c.eventHandler
		c.mu.Unlock()

		if handler != nil {
			handler(parsed.Event)
		}
	} else {
		// Send response to pending request
		c.mu.Lock()
		pendingChan := c.pendingResponse
		c.mu.Unlock()

		if pendingChan != nil {
			select {
			case pendingChan <- responseResult{response: parsed.Response}:
			default:
				// Channel full or closed - response lost
			}
		}
	}
}

// handleDisconnect handles an unexpected disconnection.
func (c *Client) handleDisconnect(err error) {
	c.mu.Lock()
	if !c.isConnected {
		c.mu.Unlock()
		return
	}

	c.isConnected = false
	handler := c.disconnectHandler
	pendingChan := c.pendingResponse
	c.mu.Unlock()

	// Notify pending request
	if pendingChan != nil {
		select {
		case pendingChan <- responseResult{err: NewConnectionError("disconnected", err)}:
		default:
		}
	}

	// Notify disconnect handler
	if handler != nil {
		handler(err)
	}
}

// DiscoverAndConnect attempts to discover a running AtticServer and connect to it.
// Returns nil if successful, or an error if no server was found or connection failed.
func (c *Client) DiscoverAndConnect() error {
	return c.DiscoverAndConnectWithContext(context.Background())
}

// DiscoverAndConnectWithContext attempts to discover and connect with a context.
func (c *Client) DiscoverAndConnectWithContext(ctx context.Context) error {
	socketPath := DiscoverSocket()
	if socketPath == "" {
		return ErrSocketNotFound
	}
	return c.ConnectWithContext(ctx, socketPath)
}
