"""Tests for REPL mode switching, prompt generation, and completions."""

from unittest.mock import MagicMock

from prompt_toolkit.completion import CompleteEvent
from prompt_toolkit.document import Document
from prompt_toolkit.formatted_text import HTML

from attic_cli.commands import QUIT, SHUTDOWN
from attic_cli.repl import (
    _handle_dot_with_mode,
    _mode_completer,
    _mode_prompt,
    _translate_for_mode,
)


class TestModePrompt:
    def test_monitor_prompt(self):
        prompt = _mode_prompt("monitor", 1)
        # Verify it's an HTML formatted text instance
        assert isinstance(prompt, HTML)
        assert "monitor" in prompt.value

    def test_basic_prompt(self):
        prompt = _mode_prompt("basic", 1)
        assert isinstance(prompt, HTML)
        assert "basic" in prompt.value

    def test_basic_turbo_prompt(self):
        prompt = _mode_prompt("basic_turbo", 1)
        assert isinstance(prompt, HTML)
        assert "turbo" in prompt.value

    def test_dos_prompt(self):
        prompt = _mode_prompt("dos", 1)
        assert isinstance(prompt, HTML)
        assert "dos" in prompt.value
        assert "D1:" in prompt.value

    def test_dos_prompt_drive_2(self):
        prompt = _mode_prompt("dos", 2)
        assert "D2:" in prompt.value

    def test_dos_prompt_drive_8(self):
        prompt = _mode_prompt("dos", 8)
        assert "D8:" in prompt.value


class TestModeCompleter:
    def test_monitor_completer(self):
        completer = _mode_completer("monitor", False)
        assert completer is not None
        words = completer.words
        # Should have monitor commands
        assert "g" in words
        assert "r" in words
        assert "d" in words
        # Should have global dot-commands
        assert ".help" in words
        assert ".quit" in words

    def test_basic_completer(self):
        completer = _mode_completer("basic", False)
        words = completer.words
        assert "list" in words
        assert "run" in words

    def test_dos_completer(self):
        completer = _mode_completer("dos", False)
        words = completer.words
        assert "mount" in words
        assert "dir" in words

    def test_assembly_mode_no_completer(self):
        completer = _mode_completer("monitor", True)
        assert completer is None

    def _complete(self, mode, text):
        """Helper: get completion texts for given input text."""
        completer = _mode_completer(mode, False)
        doc = Document(text, cursor_position=len(text))
        return [c.text for c in completer.get_completions(doc, CompleteEvent())]

    def test_dot_help_completes(self):
        results = self._complete("basic", ".h")
        assert ".help" in results

    def test_dot_status_completes(self):
        results = self._complete("basic", ".s")
        assert ".status" in results
        assert ".screenshot" in results
        assert ".shutdown" in results
        assert ".state" in results

    def test_dot_prefix_lists_all_dot_commands(self):
        results = self._complete("basic", ".")
        assert all(r.startswith(".") for r in results)
        assert ".help" in results
        assert ".quit" in results

    def test_mode_commands_still_complete(self):
        results = self._complete("basic", "li")
        assert "list" in results

    def test_no_dot_commands_for_plain_prefix(self):
        results = self._complete("basic", "h")
        # 'h' should not match '.help' — only bare commands
        assert ".help" not in results


class TestTranslateForMode:
    def test_monitor_dispatch(self):
        cmds = _translate_for_mode("g", "monitor")
        assert cmds == ["resume"]

    def test_basic_dispatch(self):
        cmds = _translate_for_mode("list", "basic")
        assert cmds == ["basic list atascii"]

    def test_basic_turbo_dispatch(self):
        cmds = _translate_for_mode("list", "basic_turbo")
        assert cmds == ["basic list atascii"]

    def test_dos_dispatch(self):
        cmds = _translate_for_mode("dir", "dos")
        assert cmds == ["dos dir"]

    def test_unknown_mode_passthrough(self):
        cmds = _translate_for_mode("test", "unknown")
        assert cmds == ["test"]


class TestHandleDotWithMode:
    """Tests for _handle_dot_with_mode — the fix for attic-id7."""

    def _make_client(self):
        return MagicMock()

    def test_switch_to_monitor(self):
        result = _handle_dot_with_mode(
            ".monitor", client=self._make_client(), mode="basic", current_drive=1
        )
        assert isinstance(result, dict)
        assert result["mode"] == "monitor"

    def test_switch_to_basic(self):
        result = _handle_dot_with_mode(
            ".basic", client=self._make_client(), mode="monitor", current_drive=1
        )
        assert isinstance(result, dict)
        assert result["mode"] == "basic"

    def test_switch_to_basic_turbo(self):
        result = _handle_dot_with_mode(
            ".basic turbo", client=self._make_client(), mode="basic", current_drive=1
        )
        assert isinstance(result, dict)
        assert result["mode"] == "basic_turbo"

    def test_switch_to_dos(self):
        result = _handle_dot_with_mode(
            ".dos", client=self._make_client(), mode="basic", current_drive=1
        )
        assert isinstance(result, dict)
        assert result["mode"] == "dos"

    def test_quit_returns_sentinel(self):
        result = _handle_dot_with_mode(
            ".quit", client=self._make_client(), mode="basic", current_drive=1
        )
        assert result is QUIT

    def test_unknown_command_returns_error(self):
        result = _handle_dot_with_mode(
            ".bogus", client=self._make_client(), mode="basic", current_drive=1
        )
        assert isinstance(result, str)
        assert "Unknown" in result
