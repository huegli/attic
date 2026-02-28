"""Tests for REPL mode switching, prompt generation, and completions."""

from prompt_toolkit.formatted_text import HTML

from attic_cli.repl import _mode_completer, _mode_prompt, _translate_for_mode


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
