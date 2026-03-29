# -*- mode: python ; coding: utf-8 -*-
# =============================================================================
# PyInstaller spec for the Attic CLI (Python-based terminal client)
# =============================================================================
# Builds a standalone macOS executable that embeds the Python interpreter and
# all dependencies (click, prompt-toolkit, rich). No Python installation is
# required at runtime.
#
# Usage:
#   cd Python/AtticCLI
#   uv run pyinstaller --clean --noconfirm attic.spec
#
# Output:
#   dist/attic    (single-file executable)
# =============================================================================

from PyInstaller.utils.hooks import collect_submodules

# Collect every attic_cli.* module so that late/dynamic imports
# (e.g. attic_cli.repl imported after connection is established)
# are included in the frozen bundle.
hidden = collect_submodules('attic_cli')

a = Analysis(
    ['entry_point.py'],
    pathex=[],
    binaries=[],
    datas=[],
    hiddenimports=hidden,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=['pytest', 'test', 'tests'],
    noarchive=False,
    optimize=1,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='attic',
    debug=False,
    bootloader_ignore_signals=False,
    strip=True,
    upx=False,           # UPX is unreliable on macOS ARM
    console=True,
    target_arch=None,     # Build for current architecture
)
