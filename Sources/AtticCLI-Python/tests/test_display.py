"""Tests for output formatting (display module)."""

from attic_cli.display import (
    _mnemonic_color,
    format_disassembly,
    format_memory_dump,
    format_registers,
    split_multiline,
)


class TestSplitMultiline:
    def test_single_line(self):
        assert split_multiline("hello") == ["hello"]

    def test_multi_line(self):
        assert split_multiline("a\x1eb\x1ec") == ["a", "b", "c"]

    def test_empty(self):
        assert split_multiline("") == []


class TestMnemonicColor:
    def test_load_store(self):
        assert _mnemonic_color("LDA") == "blue"
        assert _mnemonic_color("STA") == "blue"
        assert _mnemonic_color("LDX") == "blue"

    def test_arithmetic(self):
        assert _mnemonic_color("ADC") == "green"
        assert _mnemonic_color("SBC") == "green"
        assert _mnemonic_color("AND") == "green"

    def test_branch(self):
        assert _mnemonic_color("JMP") == "yellow"
        assert _mnemonic_color("JSR") == "yellow"
        assert _mnemonic_color("BEQ") == "yellow"

    def test_stack(self):
        assert _mnemonic_color("PHA") == "magenta"
        assert _mnemonic_color("PLA") == "magenta"

    def test_flag(self):
        assert _mnemonic_color("CLC") == "cyan"
        assert _mnemonic_color("SEI") == "cyan"

    def test_transfer(self):
        assert _mnemonic_color("TAX") == "white"

    def test_system(self):
        assert _mnemonic_color("BRK") == "red"
        assert _mnemonic_color("NOP") == "red"

    def test_case_insensitive(self):
        assert _mnemonic_color("lda") == "blue"

    def test_unknown(self):
        assert _mnemonic_color("XYZ") == "white"


class TestFormatRegisters:
    def test_basic_registers(self):
        result = format_registers("A=$FF X=$00 Y=$00 S=$FD P=$34 PC=$E000")
        assert "[bold]A[/bold]" in result
        assert "[cyan]$FF[/cyan]" in result
        assert "[bold]PC[/bold]" in result
        assert "[cyan]$E000[/cyan]" in result

    def test_empty(self):
        result = format_registers("")
        assert result == ""


class TestFormatDisassembly:
    def test_single_instruction(self):
        result = format_disassembly("$E000  A9 00     LDA #$00")
        assert "[dim]$E000[/dim]" in result
        assert "LDA" in result
        assert "#$00" in result

    def test_multiline(self):
        raw = "$E000  A9 00     LDA #$00\x1e$E002  8D 00 D4  STA $D400"
        result = format_disassembly(raw)
        assert "LDA" in result
        assert "STA" in result

    def test_branch_instruction(self):
        result = format_disassembly("$E010  D0 FE     BNE $E010")
        assert "[yellow]BNE[/yellow]" in result

    def test_passthrough_non_parseable(self):
        result = format_disassembly("some random text")
        assert result == "some random text"


class TestFormatMemoryDump:
    def test_basic_dump(self):
        result = format_memory_dump("$0600: A9 00 8D 00 D4 00 00 00")
        assert "[cyan]$0600[/cyan]" in result
        # Zero bytes should be dimmed
        assert "[dim]00[/dim]" in result
        # Non-zero byte should be bold
        assert "[bold]A9[/bold]" in result

    def test_io_address_highlighted(self):
        result = format_memory_dump("$D000: FF 00 42")
        assert "[bold magenta]FF[/bold magenta]" in result
        assert "[bold magenta]42[/bold magenta]" in result

    def test_with_ascii_sidebar(self):
        result = format_memory_dump("$0600: 48 45 4C 4C 4F | HELLO")
        assert "[dim]| HELLO[/dim]" in result

    def test_empty(self):
        result = format_memory_dump("")
        assert result == ""
