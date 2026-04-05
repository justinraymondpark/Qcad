#!/bin/bash
#
# build_macos.sh - Build QCAD for macOS 11 (Big Sur) and later
#
# Prerequisites:
#   - Xcode 13+ or Xcode Command Line Tools
#   - Qt 5.15.x or Qt 6.5+ installed (via Homebrew, Qt Online Installer, or qt.io)
#   - CMake 3.16+ (for CMake build path)
#
# Usage:
#   ./build_macos.sh [options]
#
# Options:
#   --qt-dir <path>       Path to Qt installation (e.g., /usr/local/opt/qt or ~/Qt/6.5.3/macosx)
#   --build-type <type>   Release or Debug (default: Release)
#   --use-cmake           Use CMake instead of qmake (default: qmake)
#   --jobs <n>            Number of parallel build jobs (default: auto-detect)
#   --arch <arch>         Target architecture: x86_64, arm64, or universal (default: native)
#   --package             Create .dmg installer after build
#   --help                Show this help message
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_TYPE="Release"
USE_CMAKE=0
JOBS=""
ARCH=""
PACKAGE=0
QT_DIR=""
MACOS_DEPLOYMENT_TARGET="11.0"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

usage() {
    head -25 "$0" | tail -15
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --qt-dir)       QT_DIR="$2"; shift 2 ;;
        --build-type)   BUILD_TYPE="$2"; shift 2 ;;
        --use-cmake)    USE_CMAKE=1; shift ;;
        --jobs)         JOBS="$2"; shift 2 ;;
        --arch)         ARCH="$2"; shift 2 ;;
        --package)      PACKAGE=1; shift ;;
        --help)         usage ;;
        *)              error "Unknown option: $1" ;;
    esac
done

# Auto-detect parallel jobs
if [[ -z "$JOBS" ]]; then
    JOBS=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
fi

# Set deployment target
export MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET"
info "macOS Deployment Target: $MACOSX_DEPLOYMENT_TARGET"

# Detect system architecture
NATIVE_ARCH=$(uname -m)
if [[ -z "$ARCH" ]]; then
    ARCH="$NATIVE_ARCH"
fi
info "Target architecture: $ARCH"

# Find Qt installation
find_qt() {
    if [[ -n "$QT_DIR" ]]; then
        if [[ -d "$QT_DIR" ]]; then
            return 0
        else
            error "Specified Qt directory does not exist: $QT_DIR"
        fi
    fi

    # Try common Qt locations
    local qt_candidates=(
        # Homebrew Qt6
        "/opt/homebrew/opt/qt@6"
        "/usr/local/opt/qt@6"
        "/opt/homebrew/opt/qt"
        "/usr/local/opt/qt"
        # Homebrew Qt5
        "/opt/homebrew/opt/qt@5"
        "/usr/local/opt/qt@5"
    )

    # Also check Qt Online Installer locations
    for ver in 6.8 6.7 6.6 6.5 5.15; do
        qt_candidates+=("$HOME/Qt/$ver/macos")
        qt_candidates+=("$HOME/Qt/$ver/clang_64")
        qt_candidates+=("/opt/Qt/$ver/macos")
        qt_candidates+=("/opt/Qt/$ver/clang_64")
    done

    for candidate in "${qt_candidates[@]}"; do
        if [[ -d "$candidate" ]]; then
            QT_DIR="$candidate"
            info "Found Qt at: $QT_DIR"
            return 0
        fi
    done

    error "Qt installation not found. Install Qt via:
  brew install qt@6        (for Qt6, recommended)
  brew install qt@5        (for Qt5)
Or specify the path with --qt-dir <path>"
}

find_qt

# Determine Qt version
detect_qt_version() {
    local qmake_bin=""
    if [[ -x "$QT_DIR/bin/qmake" ]]; then
        qmake_bin="$QT_DIR/bin/qmake"
    elif [[ -x "$QT_DIR/bin/qmake6" ]]; then
        qmake_bin="$QT_DIR/bin/qmake6"
    fi

    if [[ -n "$qmake_bin" ]]; then
        QT_VERSION=$("$qmake_bin" -query QT_VERSION 2>/dev/null || echo "unknown")
        QT_MAJOR=$(echo "$QT_VERSION" | cut -d. -f1)
        info "Qt version: $QT_VERSION"
    else
        warn "Could not detect Qt version, assuming Qt6"
        QT_MAJOR=6
        QT_VERSION="unknown"
    fi
}

detect_qt_version

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."

    # Check Xcode / CLT
    if ! xcode-select -p &>/dev/null; then
        error "Xcode Command Line Tools not installed. Run: xcode-select --install"
    fi

    # Check compiler
    if ! command -v clang++ &>/dev/null; then
        error "clang++ not found. Install Xcode or Xcode Command Line Tools."
    fi

    if [[ $USE_CMAKE -eq 1 ]]; then
        if ! command -v cmake &>/dev/null; then
            error "CMake not found. Install via: brew install cmake"
        fi
        info "CMake: $(cmake --version | head -1)"
    fi

    info "Compiler: $(clang++ --version | head -1)"
    info "Prerequisites OK"
}

check_prerequisites

# Build with qmake
build_qmake() {
    info "Building QCAD with qmake ($BUILD_TYPE)..."

    local qmake_bin="$QT_DIR/bin/qmake"
    if [[ ! -x "$qmake_bin" ]]; then
        qmake_bin="$QT_DIR/bin/qmake6"
    fi
    if [[ ! -x "$qmake_bin" ]]; then
        error "qmake not found in $QT_DIR/bin/"
    fi

    cd "$SCRIPT_DIR"

    local qmake_args=("-r" "qcad.pro")

    if [[ "$BUILD_TYPE" == "Release" ]]; then
        qmake_args+=("CONFIG+=release" "CONFIG-=debug")
    else
        qmake_args+=("CONFIG+=debug" "CONFIG-=release")
    fi

    # Architecture flags
    case "$ARCH" in
        universal)
            qmake_args+=("QMAKE_APPLE_DEVICE_ARCHS=x86_64 arm64")
            ;;
        arm64)
            qmake_args+=("QMAKE_APPLE_DEVICE_ARCHS=arm64")
            ;;
        x86_64)
            qmake_args+=("QMAKE_APPLE_DEVICE_ARCHS=x86_64")
            ;;
    esac

    info "Running qmake..."
    "$qmake_bin" "${qmake_args[@]}"

    info "Building with make -j$JOBS..."
    make -j"$JOBS"

    info "qmake build complete!"
}

# Build with CMake
build_cmake() {
    info "Building QCAD with CMake ($BUILD_TYPE)..."

    local build_dir="$SCRIPT_DIR/build_macos"
    mkdir -p "$build_dir"
    cd "$build_dir"

    local cmake_args=(
        "-DCMAKE_BUILD_TYPE=$BUILD_TYPE"
        "-DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOS_DEPLOYMENT_TARGET"
        "-DCMAKE_PREFIX_PATH=$QT_DIR"
    )

    # Architecture
    case "$ARCH" in
        universal)
            cmake_args+=("-DCMAKE_OSX_ARCHITECTURES=x86_64;arm64")
            ;;
        arm64)
            cmake_args+=("-DCMAKE_OSX_ARCHITECTURES=arm64")
            ;;
        x86_64)
            cmake_args+=("-DCMAKE_OSX_ARCHITECTURES=x86_64")
            ;;
    esac

    # Qt6 vs Qt5
    if [[ "$QT_MAJOR" == "6" ]]; then
        cmake_args+=("-DBUILD_QT6=ON")
    else
        cmake_args+=("-DBUILD_QT6=OFF")
    fi

    # Use toolchain file if present
    local toolchain="$SCRIPT_DIR/cmake/macos_toolchain.cmake"
    if [[ -f "$toolchain" ]]; then
        cmake_args+=("-DCMAKE_TOOLCHAIN_FILE=$toolchain")
    fi

    info "Running CMake configure..."
    cmake "$SCRIPT_DIR" "${cmake_args[@]}"

    info "Building with cmake --build -j$JOBS..."
    cmake --build . --config "$BUILD_TYPE" -j "$JOBS"

    info "CMake build complete!"
}

# Create macOS .app bundle
create_app_bundle() {
    info "Creating QCAD.app bundle..."

    local output_dir
    if [[ "$BUILD_TYPE" == "Release" ]]; then
        output_dir="$SCRIPT_DIR/release"
    else
        output_dir="$SCRIPT_DIR/debug"
    fi

    local app_bundle="$output_dir/QCAD.app"

    # The qmake build should already create the .app via TEMPLATE=app + macx
    if [[ ! -d "$app_bundle" ]]; then
        warn "QCAD.app not found at $app_bundle"
        # Check cmake build dir
        if [[ -d "$SCRIPT_DIR/build_macos/src/run/QCAD.app" ]]; then
            app_bundle="$SCRIPT_DIR/build_macos/src/run/QCAD.app"
        else
            warn "App bundle not found. Looking for binary..."
            return 1
        fi
    fi

    info "App bundle: $app_bundle"

    # Copy runtime resources into the bundle
    local resources_dir="$app_bundle/Contents/Resources"
    local frameworks_dir="$app_bundle/Contents/Frameworks"
    local plugins_dir="$app_bundle/Contents/PlugIns"
    mkdir -p "$resources_dir" "$frameworks_dir" "$plugins_dir"

    # Copy QCAD resources
    for dir in scripts fonts libraries linetypes patterns themes ts; do
        if [[ -d "$SCRIPT_DIR/$dir" ]]; then
            info "  Copying $dir..."
            cp -R "$SCRIPT_DIR/$dir" "$resources_dir/" 2>/dev/null || true
        fi
    done

    # Copy examples
    if [[ -d "$SCRIPT_DIR/examples" ]]; then
        cp -R "$SCRIPT_DIR/examples" "$resources_dir/"
    fi

    # Copy qt.conf
    if [[ -f "$SCRIPT_DIR/qt.conf" ]]; then
        cp "$SCRIPT_DIR/qt.conf" "$resources_dir/"
    fi

    # Copy QCAD plugins (shared libraries)
    if [[ -d "$output_dir/plugins" ]]; then
        cp -R "$output_dir/plugins/"* "$plugins_dir/" 2>/dev/null || true
    fi

    # Copy QCAD libraries
    for lib in "$output_dir"/*.dylib; do
        if [[ -f "$lib" ]]; then
            cp "$lib" "$frameworks_dir/"
        fi
    done

    info "App bundle created: $app_bundle"
    echo "$app_bundle"
}

# Deploy Qt frameworks into the app bundle
deploy_qt() {
    local app_bundle="$1"

    if [[ -z "$app_bundle" || ! -d "$app_bundle" ]]; then
        warn "No app bundle to deploy Qt into"
        return 1
    fi

    local macdeployqt="$QT_DIR/bin/macdeployqt"
    if [[ ! -x "$macdeployqt" ]]; then
        macdeployqt="$QT_DIR/bin/macdeployqt6"
    fi

    if [[ -x "$macdeployqt" ]]; then
        info "Running macdeployqt to bundle Qt frameworks..."
        "$macdeployqt" "$app_bundle" -verbose=1
    else
        warn "macdeployqt not found - Qt frameworks will not be bundled."
        warn "The app will require Qt to be installed on the target system."
    fi
}

# Create DMG installer
create_dmg() {
    local app_bundle="$1"

    if [[ -z "$app_bundle" || ! -d "$app_bundle" ]]; then
        error "Cannot create DMG: app bundle not found"
    fi

    local dmg_name="QCAD-macOS11"
    case "$ARCH" in
        universal) dmg_name="${dmg_name}-universal" ;;
        arm64)     dmg_name="${dmg_name}-arm64" ;;
        x86_64)    dmg_name="${dmg_name}-x86_64" ;;
    esac
    dmg_name="${dmg_name}.dmg"

    local dmg_path="$SCRIPT_DIR/$dmg_name"
    local staging_dir="$SCRIPT_DIR/build_macos_dmg_staging"

    info "Creating DMG: $dmg_name..."

    rm -rf "$staging_dir"
    mkdir -p "$staging_dir"

    # Copy app bundle
    cp -R "$app_bundle" "$staging_dir/"

    # Create symlink to /Applications
    ln -s /Applications "$staging_dir/Applications"

    # Create DMG
    rm -f "$dmg_path"
    hdiutil create -volname "QCAD" \
        -srcfolder "$staging_dir" \
        -ov -format UDZO \
        "$dmg_path"

    rm -rf "$staging_dir"

    info "DMG created: $dmg_path"
}

# Main build flow
main() {
    info "========================================="
    info "  QCAD macOS Build"
    info "  Target: macOS $MACOS_DEPLOYMENT_TARGET+"
    info "  Build type: $BUILD_TYPE"
    info "  Architecture: $ARCH"
    info "  Qt: $QT_VERSION ($QT_DIR)"
    info "  Build system: $(if [[ $USE_CMAKE -eq 1 ]]; then echo 'CMake'; else echo 'qmake'; fi)"
    info "  Parallel jobs: $JOBS"
    info "========================================="

    if [[ $USE_CMAKE -eq 1 ]]; then
        build_cmake
    else
        build_qmake
    fi

    local app_bundle
    app_bundle=$(create_app_bundle)

    if [[ -n "$app_bundle" && -d "$app_bundle" ]]; then
        deploy_qt "$app_bundle"

        if [[ $PACKAGE -eq 1 ]]; then
            create_dmg "$app_bundle"
        fi
    fi

    info "========================================="
    info "  Build complete!"
    info "========================================="
}

main
