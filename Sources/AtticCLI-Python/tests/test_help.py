"""Tests for the help system — ensure all commands have help text."""

from attic_cli.help import (
    BASIC_HELP,
    DOS_HELP,
    GLOBAL_HELP,
    MONITOR_HELP,
    _mode_help_dict,
)


class TestHelpCoverage:
    """Verify that help text exists for all documented commands."""

    def test_global_commands_have_help(self):
        expected = {
            "monitor", "basic", "dos", "help", "status", "screen",
            "reset", "warmstart", "screenshot", "boot", "state",
            "quit", "shutdown",
        }
        assert set(GLOBAL_HELP.keys()) >= expected

    def test_monitor_commands_have_help(self):
        expected = {"g", "s", "p", "pause", "r", "m", ">", "f", "d", "a", "b", "bp", "bc", "bl"}
        assert set(MONITOR_HELP.keys()) >= expected

    def test_basic_commands_have_help(self):
        expected = {
            "list", "del", "run", "stop", "cont", "new", "vars", "var",
            "info", "renum", "save", "load", "import", "export", "dir",
        }
        assert set(BASIC_HELP.keys()) >= expected

    def test_dos_commands_have_help(self):
        expected = {
            "mount", "unmount", "drives", "cd", "dir", "info", "type",
            "dump", "copy", "rename", "delete", "lock", "unlock",
            "export", "import", "newdisk", "format",
        }
        assert set(DOS_HELP.keys()) >= expected


class TestModeHelpDict:
    def test_monitor(self):
        assert _mode_help_dict("monitor") is MONITOR_HELP

    def test_basic(self):
        assert _mode_help_dict("basic") is BASIC_HELP

    def test_dos(self):
        assert _mode_help_dict("dos") is DOS_HELP

    def test_unknown(self):
        assert _mode_help_dict("unknown") == {}


class TestHelpTextQuality:
    """Verify help text is non-empty and well-formatted."""

    def test_all_global_help_non_empty(self):
        for cmd, text in GLOBAL_HELP.items():
            assert text.strip(), f"Global help for '{cmd}' is empty"

    def test_all_monitor_help_non_empty(self):
        for cmd, text in MONITOR_HELP.items():
            assert text.strip(), f"Monitor help for '{cmd}' is empty"

    def test_all_basic_help_non_empty(self):
        for cmd, text in BASIC_HELP.items():
            assert text.strip(), f"BASIC help for '{cmd}' is empty"

    def test_all_dos_help_non_empty(self):
        for cmd, text in DOS_HELP.items():
            assert text.strip(), f"DOS help for '{cmd}' is empty"
