"""Inline image display via Kitty graphics protocol.

Both iTerm2 and Ghostty support the Kitty graphics protocol, so a single
implementation covers our target terminals. Images are transmitted as
base64-encoded data in chunked 4096-byte segments.

Protocol: \\033_G<control-data>;<payload>\\033\\\\

Reference: https://sw.kovidgoyal.net/kitty/graphics-protocol/
"""

import base64
import os
import struct
import sys


# Maximum base64 payload per chunk (Kitty spec recommends 4096).
_CHUNK_SIZE = 4096

# Display scale factor for inline images (Atari screenshots are small
# at native resolution, so we scale up for comfortable viewing).
_DISPLAY_SCALE = 2


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

    # Read PNG dimensions from IHDR chunk to calculate display size
    cols, rows = _png_display_size(data, _DISPLAY_SCALE)
    encoded = base64.standard_b64encode(data).decode("ascii")
    _write_kitty_image(encoded, cols=cols, rows=rows)
    return True


def _png_display_size(data: bytes, scale: int) -> tuple[int, int]:
    """Read PNG dimensions from the IHDR chunk and compute display size in cells.

    PNG layout: 8-byte signature, then IHDR chunk with width/height as
    big-endian 32-bit integers at offsets 16 and 20.

    Assumes terminal cells are roughly 8px wide and 16px tall.

    Returns:
        (columns, rows) for Kitty protocol c= and r= parameters.
        Returns (0, 0) if dimensions cannot be read (omit from protocol).
    """
    if len(data) < 24:
        return (0, 0)
    try:
        width, height = struct.unpack(">II", data[16:24])
        # Typical terminal cell: ~8px wide, ~16px tall
        cols = (width * scale) // 8
        rows = (height * scale) // 16
        return (max(cols, 1), max(rows, 1))
    except struct.error:
        return (0, 0)


def _write_kitty_image(encoded: str, *, cols: int = 0, rows: int = 0) -> None:
    """Write a base64-encoded image to the terminal using Kitty protocol.

    The image is split into chunks of _CHUNK_SIZE bytes. The first chunk
    includes the control data; subsequent chunks use 'm=1' to indicate
    continuation.

    Args:
        encoded: Base64-encoded PNG data.
        cols: Display width in terminal columns (0 = native size).
        rows: Display height in terminal rows (0 = native size).
    """
    out = sys.stdout

    # q=2 suppresses terminal response (prevents garbage text in input)
    # c= and r= set display size in terminal cells for scaling
    ctrl = "f=100,a=T,q=2"
    if cols > 0 and rows > 0:
        ctrl += f",c={cols},r={rows}"

    chunks = [encoded[i : i + _CHUNK_SIZE] for i in range(0, len(encoded), _CHUNK_SIZE)]

    if len(chunks) <= 1:
        # Single chunk — send all at once
        payload = chunks[0] if chunks else ""
        out.write(f"\033_G{ctrl};{payload}\033\\")
    else:
        # First chunk: m=1 means "more data follows"
        out.write(f"\033_G{ctrl},m=1;{chunks[0]}\033\\")
        # Middle chunks: q=2 on every chunk to suppress all responses
        for chunk in chunks[1:-1]:
            out.write(f"\033_Gq=2,m=1;{chunk}\033\\")
        # Last chunk: m=0 means "final chunk"
        out.write(f"\033_Gq=2,m=0;{chunks[-1]}\033\\")

    out.write("\n")
    out.flush()
