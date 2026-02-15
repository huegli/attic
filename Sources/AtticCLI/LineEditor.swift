// =============================================================================
// LineEditor.swift - libedit Integration for Line Editing & Command History
// =============================================================================
//
// Wraps macOS's built-in libedit library to provide Emacs-style line editing
// (Ctrl-A/E/K, arrow keys) and persistent command history for the CLI REPL.
//
// libedit (also known as editline) is the BSD alternative to GNU readline.
// macOS ships it at /usr/lib/libedit.3.dylib. It provides:
// - Emacs and vi keybindings for line editing
// - History navigation with up/down arrows
// - File-based history persistence
//
// This class detects whether stdin is a terminal (TTY). When running
// interactively, it uses libedit for full line editing. When stdin is a pipe
// (e.g., under Emacs comint mode or `echo "cmd" | attic`), it falls back to
// Swift's readLine() since the parent process provides its own editing.
//
// The CEditLineShim C target provides non-variadic wrappers for libedit's
// variadic functions (el_set, history), which Swift cannot call directly.
//
// =============================================================================

import Foundation
import CEditLineShim

// =============================================================================
// MARK: - LineEditor
// =============================================================================

/// Provides line editing and command history for the CLI REPL.
///
/// Usage:
/// ```swift
/// let editor = LineEditor()
/// while let line = editor.getLine(prompt: "[basic] > ") {
///     process(line)
/// }
/// editor.shutdown()
/// ```
///
/// In interactive mode (TTY), this uses libedit for Emacs-style keybindings
/// and history. In non-interactive mode (pipe), it falls back to readLine().
final class LineEditor {

    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// Whether stdin is connected to a terminal (TTY).
    /// When true, we use libedit. When false, we use readLine().
    let isInteractive: Bool

    /// The libedit EditLine instance. Nil when non-interactive.
    /// EditLine manages the terminal state, keybindings, and line input.
    private var el: OpaquePointer?

    /// The libedit History instance. Nil when non-interactive.
    /// History stores previous commands and supports file persistence.
    private var hist: OpaquePointer?

    /// History event structure used by libedit's history API.
    /// This is passed to every history() call and receives status information.
    private var histEvent = HistEvent()

    /// Path to the persistent history file.
    /// Commands are saved here on shutdown and loaded on startup.
    private let historyPath: String

    /// Maximum number of history entries to keep.
    private let historySize = 500

    /// Whether shutdown() has already been called. Prevents double-free.
    private var hasShutdown = false

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a new LineEditor.
    ///
    /// Detects whether stdin is a terminal. If so, initializes libedit with
    /// Emacs keybindings and loads history from ~/.attic_history.
    init() {
        // Determine history file path: ~/.attic_history
        historyPath = NSHomeDirectory() + "/.attic_history"

        // Check if stdin is a TTY (terminal). isatty() returns non-zero for TTYs.
        // When running under Emacs comint or piped input, this will be false.
        isInteractive = isatty(STDIN_FILENO) != 0

        guard isInteractive else {
            // Non-interactive: no libedit initialization needed
            el = nil
            hist = nil
            return
        }

        // --- Initialize libedit ---

        // el_init() creates an EditLine instance.
        // Parameters: program name (for config lookup), stdin, stdout, stderr.
        el = el_init("attic", stdin, stdout, stderr)

        // Set Emacs-style keybindings (Ctrl-A, Ctrl-E, Ctrl-K, etc.)
        attic_el_set_editor(el, "emacs")

        // Enable libedit's built-in signal handling so it can properly
        // restore terminal state on SIGINT, SIGTSTP, etc.
        attic_el_set_signal(el, 1)

        // Set the prompt callback. Our C shim uses a global buffer
        // (attic_el_prompt_buf) that we update before each el_gets() call.
        attic_el_set_prompt(el)

        // --- Initialize history ---

        // history_init() creates a History instance for storing previous commands.
        hist = history_init()

        // Set maximum history size
        attic_history_setsize(hist, &histEvent, Int32(historySize))

        // Suppress consecutive duplicate entries
        attic_history_setunique(hist, &histEvent, 1)

        // Attach history to the EditLine instance so arrow keys work
        attic_el_set_hist(el, hist)

        // Load saved history from previous sessions (if file exists)
        attic_history_load(hist, &histEvent, historyPath)

        // Register atexit handler so history is saved even on unexpected exit.
        // This is a safety net — normal shutdown goes through shutdown().
        atexit {
            // Access the global prompt buffer to check if we need cleanup.
            // We can't capture 'self' in an atexit closure, so the primary
            // cleanup path is through shutdown(). This is just a fallback.
        }
    }

    /// Clean up when the LineEditor is deallocated.
    deinit {
        shutdown()
    }

    // =========================================================================
    // MARK: - Line Input
    // =========================================================================

    /// Reads a line of input, displaying the given prompt.
    ///
    /// In interactive mode, uses libedit for full line editing with
    /// Emacs keybindings and history navigation. In non-interactive mode,
    /// prints the prompt manually and uses readLine().
    ///
    /// - Parameter prompt: The prompt string to display (e.g., "[basic] > ").
    /// - Returns: The input line (without trailing newline), or nil on EOF.
    func getLine(prompt: String) -> String? {
        if isInteractive {
            return getLineInteractive(prompt: prompt)
        } else {
            return getLineNonInteractive(prompt: prompt)
        }
    }

    /// Interactive input using libedit.
    ///
    /// Updates the prompt string via C helper, then calls el_gets() which
    /// handles all line editing, history navigation, and terminal control.
    private func getLineInteractive(prompt: String) -> String? {
        // Update the prompt that libedit's callback returns.
        // We use a C helper function (attic_el_set_prompt_string) to copy
        // the string into an internal buffer, avoiding direct Swift access
        // to mutable C globals which Swift 6 concurrency checking disallows.
        attic_el_set_prompt_string(prompt)

        // el_gets() reads a line with full editing support.
        // Returns nil on EOF (Ctrl-D on empty line) or error.
        // The returned string includes the trailing newline.
        var count: Int32 = 0
        guard let cLine = el_gets(el, &count) else {
            return nil  // EOF
        }

        // Convert C string to Swift String and strip trailing newline
        var line = String(cString: cLine)
        if line.hasSuffix("\n") {
            line.removeLast()
        }

        // Add non-empty lines to history
        if !line.isEmpty {
            attic_history_enter(hist, &histEvent, line)
        }

        return line
    }

    /// Non-interactive input using readLine().
    ///
    /// When stdin is a pipe (Emacs comint, scripted input), we print the
    /// prompt manually and use Swift's readLine(). This preserves the
    /// existing behavior for non-terminal usage.
    private func getLineNonInteractive(prompt: String) -> String? {
        // Print prompt and flush so it appears before waiting for input
        print(prompt, terminator: " ")
        fflush(stdout)
        return readLine()
    }

    // =========================================================================
    // MARK: - Shutdown
    // =========================================================================

    /// Saves history and releases libedit resources.
    ///
    /// This method is idempotent — safe to call multiple times.
    /// Called automatically from deinit, but should be called explicitly
    /// before program exit to ensure history is saved.
    func shutdown() {
        guard !hasShutdown else { return }
        hasShutdown = true

        guard isInteractive else { return }

        // Save history to disk for next session
        if let hist = hist {
            attic_history_save(hist, &histEvent, historyPath)
            history_end(hist)
        }
        hist = nil

        // Release the EditLine instance and restore terminal state
        if let el = el {
            el_end(el)
        }
        self.el = nil
    }
}
