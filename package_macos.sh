#!/bin/bash
#
# package_macos.sh - Package QCAD into a distributable macOS .app bundle and .dmg
#
# This script takes a built QCAD and creates a self-contained .app bundle
# with all Qt frameworks and QCAD resources bundled inside.
#
# Usage:
#   ./package_macos.sh [options]
#
# Options:
#   --qt-dir <path>       Path to Qt installation
#   --build-dir <path>    Path to build output (default: ./release)
#   --arch <arch>         Architecture label for DMG name (x86_64, arm64, universal)
#   --sign <identity>     Code signing identity (optional)
#   --notarize            Notarize the DMG (requires Apple Developer account)
#   --help                Show this help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/release"
QT_DIR=""
ARCH=""
SIGN_IDENTITY=""
NOTARIZE=0
VERSION="3.32"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --qt-dir)       QT_DIR="$2"; shift 2 ;;
        --build-dir)    BUILD_DIR="$2"; shift 2 ;;
        --arch)         ARCH="$2"; shift 2 ;;
        --sign)         SIGN_IDENTITY="$2"; shift 2 ;;
        --notarize)     NOTARIZE=1; shift ;;
        --help)         head -18 "$0" | tail -12; exit 0 ;;
        *)              error "Unknown option: $1" ;;
    esac
done

if [[ -z "$ARCH" ]]; then
    ARCH=$(uname -m)
fi

# Find app bundle
APP_BUNDLE=""
for candidate in "$BUILD_DIR/QCAD.app" "$SCRIPT_DIR/build_macos/src/run/QCAD.app"; do
    if [[ -d "$candidate" ]]; then
        APP_BUNDLE="$candidate"
        break
    fi
done

if [[ -z "$APP_BUNDLE" ]]; then
    error "QCAD.app not found. Build the project first with ./build_macos.sh"
fi

info "Packaging: $APP_BUNDLE"

CONTENTS="$APP_BUNDLE/Contents"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"
PLUGINS="$CONTENTS/PlugIns"

mkdir -p "$RESOURCES" "$FRAMEWORKS" "$PLUGINS"

# Copy QCAD runtime resources
info "Copying QCAD resources..."
for dir in scripts fonts libraries linetypes patterns themes ts examples; do
    if [[ -d "$SCRIPT_DIR/$dir" ]]; then
        rsync -a --delete "$SCRIPT_DIR/$dir/" "$RESOURCES/$dir/"
    fi
done

# Copy qt.conf into Resources
cat > "$RESOURCES/qt.conf" << 'QTCONF'
[Paths]
Plugins = PlugIns
Imports = Resources/qml
Qml2Imports = Resources/qml
QTCONF'

# Copy QCAD plugins/libraries
info "Copying QCAD libraries..."
for lib in "$BUILD_DIR"/*.dylib; do
    if [[ -f "$lib" ]]; then
        cp "$lib" "$FRAMEWORKS/"
    fi
done

# Copy plugin directories
if [[ -d "$BUILD_DIR/plugins" ]]; then
    cp -R "$BUILD_DIR/plugins/"* "$PLUGINS/" 2>/dev/null || true
fi

# Run macdeployqt to bundle Qt frameworks
if [[ -n "$QT_DIR" ]]; then
    MACDEPLOYQT="$QT_DIR/bin/macdeployqt"
    if [[ ! -x "$MACDEPLOYQT" ]]; then
        MACDEPLOYQT="$QT_DIR/bin/macdeployqt6"
    fi

    if [[ -x "$MACDEPLOYQT" ]]; then
        info "Running macdeployqt..."
        "$MACDEPLOYQT" "$APP_BUNDLE" -verbose=1
    else
        warn "macdeployqt not found at $QT_DIR/bin/"
    fi
else
    # Try to find macdeployqt in PATH
    if command -v macdeployqt &>/dev/null; then
        info "Running macdeployqt from PATH..."
        macdeployqt "$APP_BUNDLE" -verbose=1
    elif command -v macdeployqt6 &>/dev/null; then
        info "Running macdeployqt6 from PATH..."
        macdeployqt6 "$APP_BUNDLE" -verbose=1
    else
        warn "macdeployqt not found. Qt frameworks will not be bundled."
    fi
fi

# Fix RPATH for QCAD libraries in Frameworks
info "Fixing library paths..."
for lib in "$FRAMEWORKS"/*.dylib; do
    if [[ -f "$lib" ]]; then
        install_name_tool -add_rpath "@executable_path/../Frameworks" "$lib" 2>/dev/null || true
    fi
done

# Code signing
if [[ -n "$SIGN_IDENTITY" ]]; then
    info "Code signing with identity: $SIGN_IDENTITY"

    # Sign frameworks and libraries first
    find "$APP_BUNDLE" -name "*.dylib" -o -name "*.framework" | while read -r item; do
        codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$item" 2>/dev/null || true
    done

    # Sign the app bundle
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp --deep "$APP_BUNDLE"
    info "Code signing complete"

    # Verify signature
    codesign --verify --deep --strict "$APP_BUNDLE" && info "Signature verified" || warn "Signature verification failed"
fi

# Create DMG
DMG_NAME="QCAD-${VERSION}-macOS11-${ARCH}"
DMG_PATH="$SCRIPT_DIR/${DMG_NAME}.dmg"
STAGING="$SCRIPT_DIR/.dmg_staging"

info "Creating DMG: ${DMG_NAME}.dmg"

rm -rf "$STAGING"
mkdir -p "$STAGING"

cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Create a background note
cat > "$STAGING/.background_notice" << 'EOF'
Drag QCAD to Applications to install.
Requires macOS 11 (Big Sur) or later.
EOF

rm -f "$DMG_PATH"
hdiutil create -volname "QCAD $VERSION" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

rm -rf "$STAGING"

# Notarize if requested
if [[ $NOTARIZE -eq 1 && -n "$SIGN_IDENTITY" ]]; then
    info "Submitting for notarization..."
    xcrun notarytool submit "$DMG_PATH" --wait --keychain-profile "AC_PASSWORD" || warn "Notarization failed"
    xcrun stapler staple "$DMG_PATH" || warn "Stapling failed"
fi

info "========================================="
info "  Packaging complete!"
info "  DMG: $DMG_PATH"
info "  App: $APP_BUNDLE"
info "========================================="
