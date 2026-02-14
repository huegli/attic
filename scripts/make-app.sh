#!/bin/bash
# =============================================================================
# make-app.sh - Build Attic.app macOS application bundle
# =============================================================================
#
# Assembles a proper macOS .app bundle from Swift Package Manager build output.
# The bundle includes:
#   - AtticGUI executable (the main app)
#   - AtticServer executable (launched as subprocess by AtticGUI)
#   - App icon (generated from Attic-Logo.png)
#   - Info.plist (bundle metadata and file associations)
#   - Credits.rtf (shown in About dialog)
#   - ROM files if present in Resources/ROM/
#
# The resulting Attic.app can be placed in /Applications or run from anywhere.
# No code signing or notarization is performed (local use only).
#
# Usage:
#   ./scripts/make-app.sh            # Build release and create Attic.app
#   ./scripts/make-app.sh --skip-build  # Create bundle from existing build
#
# Output:
#   build/Attic.app/
# =============================================================================

set -euo pipefail

# Resolve paths relative to the project root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="Attic"
APP_DIR="$PROJECT_ROOT/build/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

# SPM release build output directory
BUILD_DIR="$PROJECT_ROOT/.build/release"

# Parse arguments
SKIP_BUILD=false
for arg in "$@"; do
    case "$arg" in
        --skip-build) SKIP_BUILD=true ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

echo "=== Building Attic.app ==="

# -------------------------------------------------------------------------
# Step 1: Build release binaries (unless --skip-build)
# -------------------------------------------------------------------------

if [ "$SKIP_BUILD" = false ]; then
    echo "Building release binaries..."
    cd "$PROJECT_ROOT"
    swift build -c release 2>&1 | tail -5
    echo "Build complete."
else
    echo "Skipping build (--skip-build)"
fi

# Verify executables exist
if [ ! -f "$BUILD_DIR/AtticGUI" ]; then
    echo "Error: AtticGUI not found at $BUILD_DIR/AtticGUI"
    echo "Run 'swift build -c release' first."
    exit 1
fi
if [ ! -f "$BUILD_DIR/AtticServer" ]; then
    echo "Error: AtticServer not found at $BUILD_DIR/AtticServer"
    echo "Run 'swift build -c release' first."
    exit 1
fi

# -------------------------------------------------------------------------
# Step 2: Create bundle directory structure
# -------------------------------------------------------------------------

echo "Creating app bundle..."

# Remove previous bundle if it exists
rm -rf "$APP_DIR"

# Create the standard macOS .app directory layout:
#   Attic.app/
#     Contents/
#       MacOS/        <- executables
#       Resources/    <- icons, credits, ROMs
#       Info.plist    <- bundle metadata
#       PkgInfo       <- legacy package type marker
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# -------------------------------------------------------------------------
# Step 3: Copy executables
# -------------------------------------------------------------------------

echo "Copying executables..."
cp "$BUILD_DIR/AtticGUI" "$MACOS_DIR/AtticGUI"
cp "$BUILD_DIR/AtticServer" "$MACOS_DIR/AtticServer"

# -------------------------------------------------------------------------
# Step 4: Generate and copy app icon
# -------------------------------------------------------------------------

echo "Generating app icon..."
"$SCRIPT_DIR/make-icon.sh" "$PROJECT_ROOT/Attic-Logo.png" "$RESOURCES_DIR/AppIcon.icns"

# -------------------------------------------------------------------------
# Step 5: Copy Info.plist and Credits.rtf
# -------------------------------------------------------------------------

echo "Copying bundle resources..."
cp "$PROJECT_ROOT/Sources/AtticGUI/Info.plist" "$CONTENTS/Info.plist"
cp "$PROJECT_ROOT/Sources/AtticGUI/Credits.rtf" "$RESOURCES_DIR/Credits.rtf"

# PkgInfo is a legacy file that helps the Finder identify the bundle type.
# "APPL????" means: application, unknown creator code.
printf 'APPL????' > "$CONTENTS/PkgInfo"

# -------------------------------------------------------------------------
# Step 6: Copy ROM files if present
# -------------------------------------------------------------------------

ROM_DIR="$PROJECT_ROOT/Resources/ROM"
if [ -d "$ROM_DIR" ] && [ "$(ls -A "$ROM_DIR" 2>/dev/null)" ]; then
    echo "Copying ROM files..."
    mkdir -p "$RESOURCES_DIR/ROM"
    cp "$ROM_DIR"/*.ROM "$RESOURCES_DIR/ROM/" 2>/dev/null || true
    cp "$ROM_DIR"/*.rom "$RESOURCES_DIR/ROM/" 2>/dev/null || true
fi

# -------------------------------------------------------------------------
# Step 7: Summary
# -------------------------------------------------------------------------

echo ""
echo "=== Attic.app created ==="
echo "Location: $APP_DIR"
echo ""

# Show bundle contents
echo "Contents:"
find "$APP_DIR" -type f | sort | while read -r f; do
    size=$(stat -f%z "$f" 2>/dev/null || echo "?")
    rel="${f#$APP_DIR/}"
    printf "  %-50s %s bytes\n" "$rel" "$size"
done

echo ""
echo "To run: open $APP_DIR"
echo "To install: cp -r $APP_DIR /Applications/"
