"""Tests for the CLI socket client helpers."""

import pytest

from attic_cli.cli_client import escape_for_inject, parse_hex_bytes, translate_key


class TestParseHexBytes:
    def test_comma_separated(self):
        assert parse_hex_bytes("A9,00,8D") == [0xA9, 0x00, 0x8D]

    def test_space_separated(self):
        assert parse_hex_bytes("A9 00 8D") == [0xA9, 0x00, 0x8D]

    def test_dollar_prefix(self):
        assert parse_hex_bytes("$A9,$00,$8D") == [0xA9, 0x00, 0x8D]

    def test_mixed_format(self):
        assert parse_hex_bytes("$A9 00,$8D") == [0xA9, 0x00, 0x8D]

    def test_single_byte(self):
        assert parse_hex_bytes("FF") == [0xFF]

    def test_empty_raises(self):
        with pytest.raises(ValueError, match="Empty"):
            parse_hex_bytes("")

    def test_out_of_range_raises(self):
        with pytest.raises(ValueError):
            parse_hex_bytes("1FF")  # 511 > 255

    def test_invalid_hex_raises(self):
        with pytest.raises(ValueError):
            parse_hex_bytes("GG")


class TestEscapeForInject:
    def test_space_escaped(self):
        assert escape_for_inject("HELLO WORLD") == "HELLO\\sWORLD"

    def test_newline_escaped(self):
        assert escape_for_inject("A\nB") == "A\\nB"

    def test_tab_escaped(self):
        assert escape_for_inject("A\tB") == "A\\tB"

    def test_carriage_return_escaped(self):
        assert escape_for_inject("A\rB") == "A\\rB"

    def test_backslash_escaped(self):
        assert escape_for_inject("A\\B") == "A\\\\B"

    def test_combined(self):
        assert escape_for_inject("10 PRINT\n") == "10\\sPRINT\\n"

    def test_empty_string(self):
        assert escape_for_inject("") == ""

    def test_no_escaping_needed(self):
        assert escape_for_inject("HELLO") == "HELLO"


class TestTranslateKey:
    def test_return(self):
        assert translate_key("RETURN") == "\n"

    def test_enter(self):
        assert translate_key("ENTER") == "\n"

    def test_space(self):
        assert translate_key("SPACE") == " "

    def test_tab(self):
        assert translate_key("TAB") == "\t"

    def test_esc(self):
        assert translate_key("ESC") == "\x1b"

    def test_escape(self):
        assert translate_key("ESCAPE") == "\x1b"

    def test_delete(self):
        assert translate_key("DELETE") == "\x7f"

    def test_backspace(self):
        assert translate_key("BACKSPACE") == "\x7f"

    def test_break(self):
        assert translate_key("BREAK") == "\x03"

    def test_case_insensitive(self):
        assert translate_key("return") == "\n"
        assert translate_key("Return") == "\n"

    def test_shift_key(self):
        assert translate_key("SHIFT+A") == "A"
        assert translate_key("SHIFT+z") == "Z"

    def test_ctrl_key(self):
        assert translate_key("CTRL+C") == "\x03"  # 67 - 64 = 3
        assert translate_key("CTRL+A") == "\x01"  # 65 - 64 = 1

    def test_single_char_passthrough(self):
        assert translate_key("A") == "A"
        assert translate_key("5") == "5"

    def test_unrecognized_passthrough(self):
        assert translate_key("F1") == "F1"
