#!/bin/bash
# =============================================================================
# make-icon.sh - Convert Attic-Logo.png to macOS .icns format
# =============================================================================
#
# Generates an AppIcon.icns file from the source PNG using macOS built-in tools
# (sips for resizing, iconutil for .icns creation).
#
# The .iconset directory must contain specific filenames at specific pixel sizes.
# macOS expects both 1x and 2x variants, where the 2x variant of size N is the
# same pixel dimensions as the 1x variant of size 2N.
#
# Usage:
#   ./scripts/make-icon.sh [source.png] [output.icns]
#
# Defaults:
#   source: Attic-Logo.png (project root)
#   output: build/AppIcon.icns
# =============================================================================

set -euo pipefail

# Resolve paths relative to the project root (parent of scripts/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SOURCE="${1:-$PROJECT_ROOT/Attic-Logo.png}"
OUTPUT="${2:-$PROJECT_ROOT/build/AppIcon.icns}"

if [ ! -f "$SOURCE" ]; then
    echo "Error: Source image not found: $SOURCE"
    exit 1
fi

# Create a temporary .iconset directory
# macOS iconutil requires a directory named *.iconset with specific filenames.
ICONSET_DIR=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET_DIR"

# Generate each required size.
# The naming convention is: icon_<size>x<size>.png for 1x,
# icon_<size>x<size>@2x.png for 2x (which is 2*size pixels).
SIZES=(16 32 64 128 256 512)

for size in "${SIZES[@]}"; do
    # 1x variant
    sips -z "$size" "$size" "$SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}.png" > /dev/null 2>&1

    # 2x variant (double the pixel dimensions)
    double=$((size * 2))
    sips -z "$double" "$double" "$SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" > /dev/null 2>&1
done

# Also add the 512x512@2x which is 1024x1024 (the source image itself)
cp "$SOURCE" "$ICONSET_DIR/icon_512x512@2x.png"

# Create the output directory if needed
mkdir -p "$(dirname "$OUTPUT")"

# Convert the .iconset directory to a single .icns file
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT"

# Clean up the temporary directory
rm -rf "$(dirname "$ICONSET_DIR")"

echo "Created: $OUTPUT"
