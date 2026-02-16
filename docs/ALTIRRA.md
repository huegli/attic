# Altirra ROMs: AltirraOS Kernel & Altirra BASIC

This document describes how to build the **AltirraOS Kernel ROM** and **Altirra BASIC ROM** from the Altirra project source code included in the `Altirra/` directory. These are open-source replacements for the proprietary Atari XL OS and Atari BASIC ROMs, allowing the Attic emulator to run without requiring original Atari ROM dumps.

## Overview

The [Altirra](https://www.virtualdub.org/altirra.html) project by Avery Lee is a cycle-accurate Atari 8-bit emulator for Windows. It includes clean-room replacement ROMs:

- **AltirraOS Kernel** (`kernelxl.rom`) -- A replacement for the Atari XL/XE OS ROM (`ATARIXL.ROM`). Loaded at `$C000-$FFFF` (16 KB).
- **Altirra BASIC** (`atbasic.bin`) -- A replacement for Atari BASIC (`ATARIBAS.ROM`). An 8K cartridge ROM loaded at `$A000-$BFFF`.

Both ROMs are written in 6502 assembly and assembled using the **MADS** (Mad Assembler) cross-assembler.

## Source Location

The Altirra 4.40 source tree is located at:

```
Altirra/
├── Copying                     # GPLv2 license (applies to the emulator itself)
├── src/
│   ├── Kernel/                 # AltirraOS kernel source
│   │   ├── source/
│   │   │   ├── main.xasm       # Main kernel entry point
│   │   │   ├── loader.xasm     # Boot loader
│   │   │   └── Shared/         # Shared includes (CIO, SIO, math pack, etc.)
│   │   ├── Makefile            # Windows nmake Makefile
│   │   └── autobuild/          # Auto-generated build files
│   ├── ATBasic/                # Altirra BASIC source
│   │   ├── source/
│   │   │   ├── atbasic.s       # Main BASIC entry point
│   │   │   ├── data.s          # Data tables
│   │   │   ├── evaluator.s     # Expression evaluator
│   │   │   ├── exec.s          # Statement execution
│   │   │   ├── functions.s     # Built-in functions
│   │   │   ├── io.s            # I/O operations
│   │   │   ├── math.s          # Math routines
│   │   │   ├── parser.s        # BASIC line parser
│   │   │   └── ...             # Other modules
│   │   └── makefile            # Windows nmake Makefile
│   └── BUILD-HOWTO.html        # Altirra build instructions (for the full emulator)
```

## Licensing

**Important:** The AltirraOS kernel and Altirra BASIC have a **permissive license** that is separate from the GPLv2 license covering the Altirra emulator itself. From the source file headers:

> Copying and distribution of this file, with or without modification,
> are permitted in any medium without royalty provided the copyright
> notice and this notice are preserved. This file is offered as-is,
> without any warranty.

This means the ROM binaries can be freely redistributed with the Attic project without GPL obligations, as long as the copyright notice is preserved.

The Altirra emulator as a whole (the Windows application) is licensed under GPLv2.

## Prerequisites

### MADS Assembler

The only tool required to build the ROMs is **MADS** (Mad Assembler), a 6502/65816 cross-assembler written in Free Pascal.

- **Homepage:** http://mads.atari8.info/
- **Source code:** https://github.com/tebe6502/Mad-Assembler
- **Minimum version:** 2.1.0 (per Altirra's BUILD-HOWTO; older versions may corrupt floating-point constants in the math pack)

#### Installing MADS on macOS

1. Install Free Pascal Compiler:
   ```bash
   brew install fpc
   ```

2. Clone and build MADS:
   ```bash
   git clone https://github.com/tebe6502/Mad-Assembler.git
   cd Mad-Assembler
   fpc -Mdelphi -vh -O3 mads.pas
   ```

3. Copy the resulting `mads` binary to your PATH:
   ```bash
   sudo cp mads /usr/local/bin/
   ```

#### Verify installation

```bash
mads
```

You should see MADS version and usage information.

## Building the ROMs

The original Altirra Makefiles use Windows `nmake` syntax with backslash paths. The commands below are the equivalent MADS invocations adapted for Unix shells (macOS/Linux).

### Building AltirraOS Kernel (XL/XE version)

This builds the 16 KB XL/XE kernel ROM, equivalent to `ATARIXL.ROM`:

```bash
cd Altirra/src/Kernel

# Create output directory
mkdir -p out

# Assemble the XL/XE kernel
mads -i:autobuild -i:autobuild_default \
     -d:_KERNEL_XLXE=1 \
     -s -p \
     -i:source/Shared \
     -b:\$c000 \
     -l:out/kernelxl.lst \
     -t:out/kernelxl.lab \
     -o:out/kernelxl.rom \
     source/main.xasm
```

**Note:** If MADS reports an error about the `autobuild_default` include path not existing, create an empty directory:
```bash
mkdir -p autobuild_default
```

The `-d:_KERNEL_XLXE=1` flag selects the XL/XE kernel variant. The `-b:$c000` flag sets the base address to `$C000` (the XL/XE OS ROM starts at this address and extends to `$FFFF`).

**Output:** `out/kernelxl.rom` (16,384 bytes)

#### MADS flag reference

| Flag | Meaning |
|------|---------|
| `-i:path` | Add include search path |
| `-d:SYMBOL=VALUE` | Define an assembly-time symbol |
| `-s` | Silent mode (suppress informational output) |
| `-p` | Print listing |
| `-b:$ADDR` | Set binary origin (base address) |
| `-l:file` | Write listing file |
| `-t:file` | Write label table file |
| `-o:file` | Set output file |

### Building Altirra BASIC

This builds the 8 KB BASIC cartridge ROM, equivalent to `ATARIBAS.ROM`:

```bash
cd Altirra/src/ATBasic

# Create output directory
mkdir -p out

# Assemble Altirra BASIC as a cartridge ROM
mads -c -s \
     -d:CART=1 \
     -b:\$a000 \
     -o:out/atbasic.bin \
     -l:out/atbasic.lst \
     -t:out/atbasic.lab \
     source/atbasic.s
```

The `-d:CART=1` flag builds BASIC as a cartridge (raw ROM image at `$A000`). Using `-d:CART=0` instead produces an XEX executable, which is not what we need for ROM replacement.

**Output:** `out/atbasic.bin` (8,192 bytes)

### Quick Build Script

For convenience, here is a complete build script that assembles both ROMs:

```bash
#!/bin/bash
# build-altirra-roms.sh -- Build AltirraOS Kernel and BASIC ROMs
#
# Usage: ./build-altirra-roms.sh [output_dir]
# Default output: Resources/ROM/

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALTIRRA_DIR="${SCRIPT_DIR}/Altirra/src"
OUTPUT_DIR="${1:-${SCRIPT_DIR}/Resources/ROM}"

# Check for MADS
if ! command -v mads &> /dev/null; then
    echo "Error: MADS assembler not found in PATH."
    echo "See docs/ALTIRRA.md for installation instructions."
    exit 1
fi

echo "MADS assembler: $(command -v mads)"
mkdir -p "${OUTPUT_DIR}"

# --- Build AltirraOS Kernel (XL/XE) ---
echo ""
echo "=== Building AltirraOS Kernel (XL/XE) ==="
cd "${ALTIRRA_DIR}/Kernel"
mkdir -p out autobuild_default

mads -i:autobuild -i:autobuild_default \
     -d:_KERNEL_XLXE=1 \
     -s -p \
     -i:source/Shared \
     -b:\$c000 \
     -l:out/kernelxl.lst \
     -t:out/kernelxl.lab \
     -o:out/kernelxl.rom \
     source/main.xasm

if [ -f out/kernelxl.rom ]; then
    SIZE=$(wc -c < out/kernelxl.rom)
    echo "Built kernelxl.rom (${SIZE} bytes)"
    cp out/kernelxl.rom "${OUTPUT_DIR}/ATARIXL.ROM"
    echo "Copied to ${OUTPUT_DIR}/ATARIXL.ROM"
else
    echo "Error: kernelxl.rom was not created"
    exit 1
fi

# --- Build Altirra BASIC ---
echo ""
echo "=== Building Altirra BASIC ==="
cd "${ALTIRRA_DIR}/ATBasic"
mkdir -p out

mads -c -s \
     -d:CART=1 \
     -b:\$a000 \
     -o:out/atbasic.bin \
     -l:out/atbasic.lst \
     -t:out/atbasic.lab \
     source/atbasic.s

if [ -f out/atbasic.bin ]; then
    SIZE=$(wc -c < out/atbasic.bin)
    echo "Built atbasic.bin (${SIZE} bytes)"
    cp out/atbasic.bin "${OUTPUT_DIR}/ATARIBAS.ROM"
    echo "Copied to ${OUTPUT_DIR}/ATARIBAS.ROM"
else
    echo "Error: atbasic.bin was not created"
    exit 1
fi

echo ""
echo "=== Build complete ==="
echo "ROM files in ${OUTPUT_DIR}:"
ls -la "${OUTPUT_DIR}/ATARIXL.ROM" "${OUTPUT_DIR}/ATARIBAS.ROM"
```

Save this as `build-altirra-roms.sh` in the project root and run:

```bash
chmod +x build-altirra-roms.sh
./build-altirra-roms.sh
```

This will build both ROMs and copy them to `Resources/ROM/` where the Attic emulator expects to find them.

## Using the ROMs with Attic

Once built, the ROM files should be placed in `Resources/ROM/` (or the directory specified by `--rom-path`):

| Built file | Copy to | Replaces |
|------------|---------|----------|
| `kernelxl.rom` | `Resources/ROM/ATARIXL.ROM` | Atari XL/XE OS ROM |
| `atbasic.bin` | `Resources/ROM/ATARIBAS.ROM` | Atari BASIC cartridge ROM |

The Attic emulator will load these files at startup. No configuration changes are needed if the files are placed in the default ROM directory.

## Other Kernel Variants

The Altirra source can also build these additional kernel variants (not typically needed for Attic):

| Target | Description | Base Address | Build flag |
|--------|-------------|-------------|------------|
| `kernel.rom` | 400/800 OS kernel | `$D800` | `_KERNEL_XLXE=0` |
| `kernelxl.rom` | **XL/XE/XEGS kernel** (recommended) | `$C000` | `_KERNEL_XLXE=1` |
| `kernel816.rom` | 65C816 kernel | `$C000` | `_KERNEL_XLXE=1 _KERNEL_816=1` |

## Troubleshooting

### "Cannot find MADS assembler"
Ensure `mads` is in your PATH. Run `which mads` to verify.

### MADS version too old
The Altirra build requires MADS 2.1.0 or newer. Older versions may silently corrupt floating-point constants in the math pack, leading to incorrect arithmetic in BASIC. Check with `mads` (version is shown in the banner).

### Include path errors
The MADS `-i:` flag uses colon as a separator (not `=`). Ensure paths use forward slashes on macOS/Linux. If `autobuild_default` is missing, create an empty directory.

### Output ROM is wrong size
- `kernelxl.rom` should be exactly 16,384 bytes (16 KB)
- `atbasic.bin` should be exactly 8,192 bytes (8 KB)

If sizes differ, check for MADS warnings about address overlaps or missing includes.

## References

- Altirra project: https://www.virtualdub.org/altirra.html
- Altirra source (included): `Altirra/` directory
- MADS assembler: http://mads.atari8.info/
- MADS source: https://github.com/tebe6502/Mad-Assembler
- Altirra version included: **4.40** (December 31, 2025)
- AltirraOS kernel version: **3.44**
- Altirra BASIC version: **1.59**
