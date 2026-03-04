"""Tests for output formatting (display module)."""

from attic_cli.display import (
    _mnemonic_color,
    format_disassembly,
    format_memory_dump,
    format_monitor_response,
    format_raw_memory_data,
    format_registers,
    split_multiline,
)

# Backward-compatible alias used by existing tests
_format_raw_data = format_raw_memory_data


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


class TestFormatRawData:
    """Tests for converting raw server 'data' responses into addressed hex dump lines."""

    def test_basic_conversion(self):
        result = _format_raw_data("read $0600 4", "data A9,00,8D,00")
        assert result == "$0600: A9 00 8D 00"

    def test_multirow(self):
        # 20 bytes should produce 2 rows (16 + 4)
        bytes_hex = ",".join(["FF"] * 16 + ["AA"] * 4)
        result = _format_raw_data("read $0600 20", f"data {bytes_hex}")
        lines = result.split("\x1e")
        assert len(lines) == 2
        assert lines[0].startswith("$0600:")
        assert lines[1].startswith("$0610:")
        assert "AA" in lines[1]

    def test_io_address(self):
        result = _format_raw_data("read $D000 2", "data FF,42")
        assert result == "$D000: FF 42"

    def test_decimal_address_fallback(self):
        # Non-hex address should default to 0
        result = _format_raw_data("read notanaddr 2", "data A9,00")
        assert result.startswith("$0000:")


class TestFormatMonitorResponse:
    """Tests for the unified monitor response formatter."""

    def test_read_applies_memory_dump_formatting(self):
        result = format_monitor_response("read $0600 4", "data A9,00,8D,00")
        assert result is not None
        # Should have colored address
        assert "[cyan]$0600[/cyan]" in result
        # Zero bytes dimmed
        assert "[dim]00[/dim]" in result
        # Non-zero bytes bold
        assert "[bold]A9[/bold]" in result

    def test_read_io_range_highlighted(self):
        result = format_monitor_response("read $D000 2", "data FF,42")
        assert result is not None
        assert "[bold magenta]FF[/bold magenta]" in result

    def test_disassemble_applies_syntax_highlighting(self):
        result = format_monitor_response(
            "disassemble $E000 1",
            "$E000  A9 00     LDA #$00",
        )
        assert result is not None
        assert "LDA" in result
        assert "[dim]$E000[/dim]" in result

    def test_registers_colored(self):
        result = format_monitor_response(
            "registers",
            "A=$FF X=$00 Y=$00 S=$FD P=$34 PC=$E000",
        )
        assert result is not None
        assert "[bold]A[/bold]" in result
        assert "[cyan]$FF[/cyan]" in result

    def test_unknown_command_returns_none(self):
        result = format_monitor_response("pause", "ok")
        assert result is None

    def test_registers_without_equals_returns_none(self):
        result = format_monitor_response("registers", "no data")
        assert result is None
