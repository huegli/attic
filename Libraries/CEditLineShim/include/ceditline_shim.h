// =============================================================================
// ceditline_shim.h - Non-variadic wrappers for libedit
// =============================================================================
//
// libedit's core functions el_set() and history() are variadic C functions.
// Swift cannot call variadic C functions directly, so this shim provides
// non-variadic wrapper functions for each operation we need.
//
// Including this header also re-exports <histedit.h>, giving Swift access
// to all libedit types (EditLine, History, HistEvent) and non-variadic
// functions (el_init, el_gets, el_end, history_init, history_end).
//
// =============================================================================

#ifndef CEDITLINE_SHIM_H
#define CEDITLINE_SHIM_H

#include <histedit.h>

// =============================================================================
// MARK: - Prompt Mechanism
// =============================================================================
//
// libedit requires a C function pointer for the prompt callback. Rather than
// trying to bridge a Swift closure through C function pointers (which is
// fragile), we use a simple global buffer. Swift writes the desired prompt
// string into this buffer before each el_gets() call, and the C callback
// returns a pointer to it.

/// Update the prompt string that libedit displays before each input line.
/// Copies the given string into an internal buffer (max 255 chars + null).
/// Call this before el_gets() to change the prompt.
void attic_el_set_prompt_string(const char *prompt);

/// C callback function that returns the prompt buffer. Passed to el_set(EL_PROMPT).
char *attic_el_prompt_callback(EditLine *el);

// =============================================================================
// MARK: - el_set Wrappers
// =============================================================================
//
// Each wrapper calls el_set() with a specific EL_* constant and the
// appropriate non-variadic argument(s).

/// Set the prompt callback function (EL_PROMPT).
/// Uses our global attic_el_prompt_callback.
void attic_el_set_prompt(EditLine *el);

/// Set the editor mode (EL_EDITOR). Pass "emacs" or "vi".
void attic_el_set_editor(EditLine *el, const char *mode);

/// Enable or disable signal handling (EL_SIGNAL).
/// When enabled (flag=1), libedit handles terminal signals internally.
void attic_el_set_signal(EditLine *el, int flag);

/// Attach a History object to the EditLine instance (EL_HIST).
/// This connects the history so that arrow keys navigate history.
void attic_el_set_hist(EditLine *el, History *h);

// =============================================================================
// MARK: - history() Wrappers
// =============================================================================
//
// The history() function is also variadic. Each wrapper calls it with
// a specific H_* operation constant.

/// Set the maximum number of history entries (H_SETSIZE).
int attic_history_setsize(History *h, HistEvent *ev, int size);

/// Add a line to the history (H_ENTER).
int attic_history_enter(History *h, HistEvent *ev, const char *str);

/// Load history from a file (H_LOAD).
int attic_history_load(History *h, HistEvent *ev, const char *path);

/// Save history to a file (H_SAVE).
int attic_history_save(History *h, HistEvent *ev, const char *path);

/// Enable or disable duplicate filtering (H_SETUNIQUE).
/// When flag=1, consecutive duplicate entries are suppressed.
int attic_history_setunique(History *h, HistEvent *ev, int flag);

#endif /* CEDITLINE_SHIM_H */
