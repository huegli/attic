// =============================================================================
// ceditline_shim.c - Non-variadic wrappers for libedit
// =============================================================================
//
// Implements the wrapper functions declared in ceditline_shim.h.
// Each function calls the corresponding variadic libedit function with
// the correct arguments, making them callable from Swift.
//
// =============================================================================

#include "ceditline_shim.h"
#include <string.h>

// =============================================================================
// MARK: - Prompt Mechanism
// =============================================================================

// Internal prompt buffer. Not exposed to Swift — accessed only through
// attic_el_set_prompt_string() and attic_el_prompt_callback().
static char attic_el_prompt_buf[256] = "> ";

// Copy a prompt string into the internal buffer.
// Called from Swift before each el_gets() to update the displayed prompt.
void attic_el_set_prompt_string(const char *prompt) {
    strncpy(attic_el_prompt_buf, prompt, sizeof(attic_el_prompt_buf) - 1);
    attic_el_prompt_buf[sizeof(attic_el_prompt_buf) - 1] = '\0';
}

// Callback function for libedit's EL_PROMPT. Simply returns the internal buffer.
// The EditLine parameter is unused but required by the callback signature.
char *attic_el_prompt_callback(EditLine *el) {
    (void)el;  // Suppress unused parameter warning
    return attic_el_prompt_buf;
}

// =============================================================================
// MARK: - el_set Wrappers
// =============================================================================

void attic_el_set_prompt(EditLine *el) {
    el_set(el, EL_PROMPT, attic_el_prompt_callback);
}

void attic_el_set_editor(EditLine *el, const char *mode) {
    el_set(el, EL_EDITOR, mode);
}

void attic_el_set_signal(EditLine *el, int flag) {
    el_set(el, EL_SIGNAL, flag);
}

void attic_el_set_hist(EditLine *el, History *h) {
    el_set(el, EL_HIST, history, h);
}

// =============================================================================
// MARK: - history() Wrappers
// =============================================================================

int attic_history_setsize(History *h, HistEvent *ev, int size) {
    return history(h, ev, H_SETSIZE, size);
}

int attic_history_enter(History *h, HistEvent *ev, const char *str) {
    return history(h, ev, H_ENTER, str);
}

int attic_history_load(History *h, HistEvent *ev, const char *path) {
    return history(h, ev, H_LOAD, path);
}

int attic_history_save(History *h, HistEvent *ev, const char *path) {
    return history(h, ev, H_SAVE, path);
}

int attic_history_setunique(History *h, HistEvent *ev, int flag) {
    return history(h, ev, H_SETUNIQUE, flag);
}
