"""Full-screen TUI BASIC editor using prompt_toolkit.

Provides a built-in editor for BASIC programs with Atari 800 XL-inspired
colors.  Uses prompt_toolkit's Application(full_screen=True) to take over
the terminal, showing a title bar, text editing area, and a status bar with
key hints.

Key bindings:
    Ctrl+S  — Save and return edited text to caller
    Ctrl+Q  — Quit without saving (returns None)
    Ctrl+G  — Go to line number
    Ctrl+F  — Find text in the editor
"""

from prompt_toolkit import Application
from prompt_toolkit.buffer import Buffer
from prompt_toolkit.document import Document
from prompt_toolkit.filters import Condition
from prompt_toolkit.key_binding import KeyBindings
from prompt_toolkit.layout import (
    Float,
    FloatContainer,
    FormattedTextControl,
    HSplit,
    VSplit,
    Window,
    WindowAlign,
)
from prompt_toolkit.layout.layout import Layout
from prompt_toolkit.styles import Style
from prompt_toolkit.widgets import SearchToolbar, TextArea


# Atari 800 XL-inspired color scheme: blue background, light blue text.
ATARI_STYLE = Style.from_dict({
    # Main editor area
    "text-area":        "bg:#2b35af #7b93db",
    # Title bar at top
    "title-bar":        "bg:#1a2080 #ffffff bold",
    "title-bar.text":   "#ffffff bold",
    # Status bar at bottom
    "status-bar":       "bg:#1a2080 #7b93db",
    "status-bar.key":   "bg:#1a2080 #ffffff bold",
    # Find dialog (uses the search toolbar)
    "search":           "bg:#3b45bf #ffffff",
    "search.text":      "#ffffff",
    # Line number gutter
    "line-number":      "bg:#222a8f #5b73bb",
    "line-number.current": "bg:#222a8f #ffffff bold",
    # Go-to-line dialog
    "dialog":           "bg:#1a2080 #ffffff",
    "dialog.body":      "bg:#2b35af #7b93db",
    "dialog frame.label": "#ffffff bold",
})


def run_editor(initial_text: str = "") -> str | None:
    """Launch the full-screen TUI editor.

    Args:
        initial_text: Text to pre-populate the editor with.

    Returns:
        The edited text if the user saved (Ctrl+S), or None if they
        quit without saving (Ctrl+Q).
    """
    # Track whether the user chose to save.
    saved = False

    # -- Search toolbar (activated by Ctrl+F) --
    search_toolbar = SearchToolbar(
        vi_mode=False,
        search_buffer=Buffer(name="search-buffer"),
    )

    # -- Main text editing area --
    text_area = TextArea(
        text=initial_text,
        scrollbar=True,
        line_numbers=True,
        search_field=search_toolbar,
        style="class:text-area",
        focus_on_click=True,
    )

    # -- Title bar --
    title_bar = Window(
        content=FormattedTextControl(
            lambda: [("class:title-bar.text", " Attic BASIC Editor ")]
        ),
        height=1,
        style="class:title-bar",
    )

    # -- Status bar with key hints --
    def _status_bar_text():
        """Build the status bar showing cursor position and key hints."""
        row = text_area.document.cursor_position_row + 1
        col = text_area.document.cursor_position_col + 1
        return [
            ("class:status-bar.key", " ^S"),
            ("class:status-bar", " Save  "),
            ("class:status-bar.key", "^Q"),
            ("class:status-bar", " Quit  "),
            ("class:status-bar.key", "^G"),
            ("class:status-bar", " Goto  "),
            ("class:status-bar.key", "^F"),
            ("class:status-bar", " Find  "),
            ("class:status-bar", f"  Ln {row}, Col {col}"),
        ]

    status_bar = Window(
        content=FormattedTextControl(_status_bar_text),
        height=1,
        style="class:status-bar",
    )

    # -- Go-to-line dialog (shown as a float) --
    goto_buffer = Buffer(name="goto-buffer")
    goto_visible = [False]  # Mutable container so closures can toggle it

    # Condition filter for key bindings that should only fire when the
    # go-to-line dialog is visible.  prompt_toolkit requires a Condition
    # object (not a plain callable).
    is_goto_visible = Condition(lambda: goto_visible[0])

    goto_window = Float(
        content=HSplit([
            Window(
                content=FormattedTextControl(
                    lambda: [("class:dialog", " Go to line: ")]
                ),
                height=1,
                style="class:dialog",
            ),
            Window(
                content=goto_buffer,
                height=1,
                width=20,
                style="class:dialog.body",
            ),
        ]),
        xcursor=True,
        ycursor=True,
        top=3,
        left=2,
    )

    # -- Layout --
    body = FloatContainer(
        content=HSplit([
            title_bar,
            text_area,
            search_toolbar,
            status_bar,
        ]),
        floats=[],  # goto_window added dynamically
    )

    # -- Key bindings --
    kb = KeyBindings()

    @kb.add("c-s")
    def _save(event):
        """Save and exit the editor."""
        nonlocal saved
        saved = True
        event.app.exit()

    @kb.add("c-q")
    def _quit(event):
        """Quit without saving."""
        event.app.exit()

    @kb.add("c-g")
    def _goto_line(event):
        """Toggle the go-to-line dialog."""
        if goto_visible[0]:
            # Dialog already open — hide it and refocus editor.
            goto_visible[0] = False
            body.floats.clear()
            event.app.layout.focus(text_area)
        else:
            # Show the dialog and focus the input.
            goto_visible[0] = True
            goto_buffer.reset()
            body.floats.append(goto_window)
            event.app.layout.focus(goto_buffer)

    @kb.add("enter", filter=is_goto_visible)
    def _goto_accept(event):
        """Accept the go-to-line number and jump to that line."""
        line_text = goto_buffer.text.strip()
        goto_visible[0] = False
        body.floats.clear()
        event.app.layout.focus(text_area)

        if not line_text:
            return

        try:
            target = int(line_text)
        except ValueError:
            return

        # Jump to the target line (1-based from user, 0-based internally).
        doc = text_area.document
        lines = doc.text.splitlines(True)
        total = len(lines)
        target_row = max(0, min(target - 1, total - 1))

        # Compute character offset for the start of target_row.
        offset = sum(len(lines[i]) for i in range(target_row))
        text_area.buffer.document = Document(doc.text, cursor_position=offset)

    @kb.add("escape", filter=is_goto_visible)
    def _goto_cancel(event):
        """Cancel the go-to-line dialog."""
        goto_visible[0] = False
        body.floats.clear()
        event.app.layout.focus(text_area)

    @kb.add("c-f")
    def _find(event):
        """Start incremental search."""
        event.app.layout.focus(search_toolbar)

    # -- Application --
    app: Application = Application(
        layout=Layout(body, focused_element=text_area),
        key_bindings=kb,
        style=ATARI_STYLE,
        full_screen=True,
        mouse_support=True,
    )

    app.run()

    if saved:
        return text_area.text
    return None
