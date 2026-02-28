"""Tests for terminal image and OSC helpers."""

import os
from unittest.mock import patch

from attic_cli.terminal_images import supports_kitty_graphics
from attic_cli.terminal_osc import osc8_file_link, osc8_link


class TestKittyGraphicsDetection:
    def test_ghostty_detected(self):
        with patch.dict(os.environ, {"TERM_PROGRAM": "ghostty"}, clear=False):
            assert supports_kitty_graphics() is True

    def test_iterm2_detected(self):
        with patch.dict(os.environ, {"TERM_PROGRAM": "iTerm2"}, clear=False):
            assert supports_kitty_graphics() is True

    def test_kitty_detected(self):
        with patch.dict(os.environ, {"TERM_PROGRAM": "kitty"}, clear=False):
            assert supports_kitty_graphics() is True

    def test_wezterm_detected(self):
        with patch.dict(os.environ, {"TERM_PROGRAM": "WezTerm"}, clear=False):
            assert supports_kitty_graphics() is True

    def test_lc_terminal_fallback(self):
        with patch.dict(
            os.environ,
            {"TERM_PROGRAM": "", "TERM": "xterm", "LC_TERMINAL": "iTerm2"},
            clear=False,
        ):
            assert supports_kitty_graphics() is True

    def test_unsupported_terminal(self):
        with patch.dict(
            os.environ,
            {"TERM_PROGRAM": "Apple_Terminal", "TERM": "xterm-256color", "LC_TERMINAL": ""},
            clear=False,
        ):
            assert supports_kitty_graphics() is False


class TestOSC8:
    def test_osc8_link(self):
        result = osc8_link("https://example.com", "click here")
        assert "https://example.com" in result
        assert "click here" in result
        assert "\033]8;;" in result  # OSC 8 start

    def test_osc8_file_link_default_text(self):
        result = osc8_file_link("/tmp/test.png")
        assert "file:///tmp/test.png" in result
        assert "/tmp/test.png" in result

    def test_osc8_file_link_custom_text(self):
        result = osc8_file_link("/tmp/test.png", "screenshot")
        assert "file:///tmp/test.png" in result
        assert "screenshot" in result
