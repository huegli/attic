"""Tests for command-to-protocol translation."""

from attic_cli.translator import translate_basic, translate_dos, translate_monitor


class TestTranslateMonitor:
    def test_go_resume(self):
        assert translate_monitor("g") == ["resume"]

    def test_go_address(self):
        assert translate_monitor("g $E000") == ["registers pc=$E000", "resume"]

    def test_step(self):
        assert translate_monitor("s") == ["step"]

    def test_step_count(self):
        assert translate_monitor("s 10") == ["step 10"]

    def test_pause(self):
        assert translate_monitor("p") == ["pause"]
        assert translate_monitor("pause") == ["pause"]

    def test_until(self):
        assert translate_monitor("until $0600") == ["run_until $0600"]

    def test_registers_read(self):
        assert translate_monitor("r") == ["registers"]

    def test_registers_set(self):
        assert translate_monitor("r a=$42 pc=$E000") == ["registers a=$42 pc=$E000"]

    def test_memory_read(self):
        assert translate_monitor("m $0600") == ["read $0600"]

    def test_memory_read_with_count(self):
        assert translate_monitor("m $0600 32") == ["read $0600 32"]

    def test_memory_write(self):
        assert translate_monitor("> $0600 A9,00") == ["write $0600 A9,00"]

    def test_fill(self):
        assert translate_monitor("f $0600 $06FF $00") == ["fill $0600 $06FF $00"]

    def test_disassemble(self):
        assert translate_monitor("d") == ["disassemble"]

    def test_disassemble_address(self):
        assert translate_monitor("d $E000") == ["disassemble $E000"]

    def test_disassemble_address_lines(self):
        assert translate_monitor("d $E000 20") == ["disassemble $E000 20"]

    def test_assemble(self):
        assert translate_monitor("a $0600") == ["assemble $0600"]

    def test_assemble_inline(self):
        assert translate_monitor("a $0600 LDA #$00") == ["assemble $0600 LDA #$00"]

    def test_breakpoint_set(self):
        assert translate_monitor("b $0600") == ["breakpoint set $0600"]

    def test_breakpoint_set_bp(self):
        assert translate_monitor("bp $0600") == ["breakpoint set $0600"]

    def test_breakpoint_list_default(self):
        assert translate_monitor("b") == ["breakpoint list"]

    def test_breakpoint_clear(self):
        assert translate_monitor("bc $0600") == ["breakpoint clear $0600"]

    def test_breakpoint_clear_all(self):
        assert translate_monitor("bc *") == ["breakpoint clearall"]

    def test_breakpoint_list(self):
        assert translate_monitor("bl") == ["breakpoint list"]

    def test_passthrough(self):
        assert translate_monitor("unknown command") == ["unknown command"]

    def test_case_insensitive(self):
        assert translate_monitor("G $E000") == ["registers pc=$E000", "resume"]
        assert translate_monitor("D $E000") == ["disassemble $E000"]


class TestTranslateBasic:
    def test_list(self):
        assert translate_basic("list") == ["basic list atascii"]

    def test_list_no_atascii(self):
        assert translate_basic("list", atascii=False) == ["basic list"]

    def test_list_range(self):
        assert translate_basic("list 10-50") == ["basic list 10-50 atascii"]

    def test_del(self):
        assert translate_basic("del 30") == ["basic del 30"]

    def test_del_range(self):
        assert translate_basic("del 10-50") == ["basic del 10-50"]

    def test_stop(self):
        assert translate_basic("STOP") == ["basic stop"]

    def test_cont(self):
        assert translate_basic("CONT") == ["basic cont"]

    def test_vars(self):
        assert translate_basic("VARS") == ["basic vars"]

    def test_var_name(self):
        assert translate_basic("VAR X") == ["basic var X"]

    def test_info(self):
        assert translate_basic("INFO") == ["basic info"]

    def test_export(self):
        assert translate_basic("EXPORT ~/prog.bas") == ["basic export ~/prog.bas"]

    def test_import(self):
        assert translate_basic("IMPORT ~/prog.bas") == ["basic import ~/prog.bas"]

    def test_dir(self):
        assert translate_basic("DIR") == ["basic dir"]

    def test_dir_drive(self):
        assert translate_basic("DIR 2") == ["basic dir 2"]

    def test_renum(self):
        assert translate_basic("RENUM") == ["basic renum"]

    def test_renum_args(self):
        assert translate_basic("RENUM 100 5") == ["basic renum 100 5"]

    def test_save(self):
        assert translate_basic("SAVE D:PROG") == ["basic save D:PROG"]

    def test_load(self):
        assert translate_basic("LOAD D:PROG") == ["basic load D:PROG"]

    def test_numbered_line_injected(self):
        result = translate_basic("10 PRINT \"HELLO\"")
        assert len(result) == 1
        assert result[0].startswith("inject keys ")
        assert "\\s" in result[0]  # Spaces escaped
        assert result[0].endswith("\\n")  # Newline appended

    def test_run_injected(self):
        result = translate_basic("RUN")
        assert result == ["inject keys RUN\\n"]

    def test_new_injected(self):
        result = translate_basic("NEW")
        assert result == ["inject keys NEW\\n"]

    def test_case_insensitive(self):
        assert translate_basic("list") == ["basic list atascii"]
        assert translate_basic("List") == ["basic list atascii"]
        assert translate_basic("LIST") == ["basic list atascii"]


class TestTranslateDos:
    def test_mount(self):
        assert translate_dos("mount 1 ~/game.atr") == ["mount 1 ~/game.atr"]

    def test_unmount(self):
        assert translate_dos("unmount 1") == ["unmount 1"]

    def test_umount_alias(self):
        assert translate_dos("umount 1") == ["unmount 1"]

    def test_drives(self):
        assert translate_dos("drives") == ["drives"]

    def test_cd(self):
        assert translate_dos("cd 2") == ["dos cd 2"]

    def test_dir(self):
        assert translate_dos("dir") == ["dos dir"]

    def test_dir_pattern(self):
        assert translate_dos("dir *.BAS") == ["dos dir *.BAS"]

    def test_info(self):
        assert translate_dos("info PROG.BAS") == ["dos info PROG.BAS"]

    def test_type(self):
        assert translate_dos("type README") == ["dos type README"]

    def test_dump(self):
        assert translate_dos("dump PROG.BAS") == ["dos dump PROG.BAS"]

    def test_copy(self):
        assert translate_dos("copy SRC DST") == ["dos copy SRC DST"]

    def test_cp_alias(self):
        assert translate_dos("cp SRC DST") == ["dos copy SRC DST"]

    def test_rename(self):
        assert translate_dos("rename OLD NEW") == ["dos rename OLD NEW"]

    def test_ren_alias(self):
        assert translate_dos("ren OLD NEW") == ["dos rename OLD NEW"]

    def test_delete(self):
        assert translate_dos("delete FILE") == ["dos delete FILE"]

    def test_del_alias(self):
        assert translate_dos("del FILE") == ["dos delete FILE"]

    def test_lock(self):
        assert translate_dos("lock FILE") == ["dos lock FILE"]

    def test_unlock(self):
        assert translate_dos("unlock FILE") == ["dos unlock FILE"]

    def test_export(self):
        assert translate_dos("export FILE ~/path") == ["dos export FILE ~/path"]

    def test_import(self):
        assert translate_dos("import ~/path FILE") == ["dos import ~/path FILE"]

    def test_newdisk(self):
        assert translate_dos("newdisk ~/new.atr dd") == ["dos newdisk ~/new.atr dd"]

    def test_format(self):
        assert translate_dos("format") == ["dos format"]

    def test_case_insensitive(self):
        assert translate_dos("MOUNT 1 ~/g.atr") == ["mount 1 ~/g.atr"]
        assert translate_dos("Dir") == ["dos dir"]
