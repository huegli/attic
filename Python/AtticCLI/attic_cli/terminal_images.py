"""Inline image display via Kitty graphics protocol.

Both iTerm2 and Ghostty support the Kitty graphics protocol, so a single
implementation covers our target terminals. Images are transmitted as
base64-encoded data in chunked 4096-byte segments.

Protocol: \\033_G<control-data>;<payload>\\033\\\\

Reference: https://sw.kovidgoyal.net/kitty/graphics-protocol/
"""

import base64
import os
import sys


# Maximum base64 payload per chunk (Kitty spec recommends 4096).
_CHUNK_SIZE = 4096


def supports_kitty_graphics() -> bool:
    """Detect whether the current terminal supports the Kitty graphics protocol.

    Checks TERM_PROGRAM, TERM, and LC_TERMINAL environment variables for
    known-supporting terminals.
    """
    term_program = os.environ.get("TERM_PROGRAM", "").lower()
    term = os.environ.get("TERM", "").lower()
    lc_terminal = os.environ.get("LC_TERMINAL", "").lower()

    # Known terminals supporting Kitty graphics protocol
    kitty_terminals = {"kitty", "ghostty", "iterm2", "iterm.app", "wezterm"}

    for value in (term_program, term, lc_terminal):
        if any(t in value for t in kitty_terminals):
            return True

    return False


def display_inline_image(path: str, *, fallback_message: bool = True) -> bool:
    """Display a PNG image inline in the terminal using Kitty graphics protocol.

    Args:
        path: Filesystem path to the PNG image file.
        fallback_message: If True, print the file path when the terminal
            doesn't support inline images.

    Returns:
        True if the image was displayed, False if fallback was used.
    """
    if not supports_kitty_graphics():
        if fallback_message:
            print(f"Screenshot saved: {path}")
        return False

    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError as exc:
        print(f"Error reading image: {exc}")
        return False

    encoded = base64.standard_b64encode(data).decode("ascii")
    _write_kitty_image(encoded)
    return True


def _write_kitty_image(encoded: str) -> None:
    """Write a base64-encoded image to the terminal using Kitty protocol.

    The image is split into chunks of _CHUNK_SIZE bytes. The first chunk
    includes the control data; subsequent chunks use 'm=1' to indicate
    continuation.
    """
    out = sys.stdout

    chunks = [encoded[i : i + _CHUNK_SIZE] for i in range(0, len(encoded), _CHUNK_SIZE)]

    if len(chunks) <= 1:
        # Single chunk — send all at once
        payload = chunks[0] if chunks else ""
        out.write(f"\033_Gf=100,a=T;{payload}\033\\")
    else:
        # First chunk: m=1 means "more data follows"
        out.write(f"\033_Gf=100,a=T,m=1;{chunks[0]}\033\\")
        # Middle chunks
        for chunk in chunks[1:-1]:
            out.write(f"\033_Gm=1;{chunk}\033\\")
        # Last chunk: m=0 means "final chunk"
        out.write(f"\033_Gm=0;{chunks[-1]}\033\\")

    out.write("\n")
    out.flush()
